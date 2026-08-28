import Foundation
import SwiftData
import CoreMedia
import CoreGraphics

// 저장 계층 확인 하네스 (2-4 · 2-5 · 2-6 · 2-7 · 2-8 · 2-9 · 2-10 · 2-12 · 2-12a).
//
// Mellow/ 밖에 둔다. project.yml 의 sources 는 Mellow 디렉터리만 훑으므로
// 여기 있는 파일은 앱 타깃에 들어가지 않는다. `ExportBench.swift` 와 같은
// 자리다.
//
// **저장소에 남긴다.** 2-4·2-5 하네스가 이전 세션의 스크래치패드에만 있어
// 그대로 사라졌고, 2-7 에서 회귀를 보려다 없어서 다시 써야 했다. 흩어져
// 있으면 또 사라지므로 한 파일 · 한 명령으로 모아 둔다.
//
// 빌드와 실행:
//   swiftc -parse-as-library -D DEBUG \
//     Mellow/Models/Orientation.swift \
//     Mellow/Models/Session.swift \
//     Mellow/Models/Clip.swift \
//     Mellow/Storage/SessionFileStore.swift \
//     Mellow/Storage/SessionStore.swift \
//     Mellow/Storage/ClipStore.swift \
//     Mellow/Capture/RecordingGate.swift \
//     Mellow/Capture/CameraPermissions.swift \
//     Mellow/Diagnostics/ClipSpec.swift \
//     Mellow/Merge/ClipMerger.swift \
//     Mellow/Merge/ClipExporter.swift \
//     Mellow/Export/PhotoLibrarySaver.swift \
//     Mellow/Export/SessionExportPipeline.swift \
//     Tools/StorageCheck.swift -o /tmp/storagecheck && /tmp/storagecheck
//
// `ClipSpec.swift` 가 2-8 에서 들어왔다. 방향 도출(E군)이 그 파일의
// `VideoTrackSpec.orientation` 을 검증한다. UIKit 비의존이라 Mac 에서
// 그대로 컴파일된다 — 그 제약을 지키는 이유가 이것이다.
//
// 병합·익스포트·사진 저장 계열(`ClipMerger` 이하 4파일 + `CameraPermissions`)은
// 2-12a 에서 들어왔다. **N군이 실행하는 것이 아니라 컴파일에만 필요하다** —
// `SessionStore.init` 의 파이프라인 기본값이 `SessionExportPipeline` 을
// 참조하기 때문이다. N군 자체는 전부 스텁 파이프라인으로 돈다.
//
// **`-D DEBUG` 가 필요하다.** `SessionStore` 의 "후보가 여럿" 로그가
// `#if DEBUG` 로 감싸여 있어(세션 id·제목을 찍으므로 릴리스에서 뺐다),
// 빼고 빌드하면 6군이 확인하려는 로그가 아예 안 찍힌다. 앱의 Debug
// 빌드와 같은 조건으로 맞추는 것이기도 하다.
//
// 실패가 있으면 exit 1 이다. CoreData 가 stderr 로 뱉는 소음은 무시해도 된다 —
// 저장 실패를 일부러 유도하는 구간에서 나온다.
//
// 카메라가 필요 없는 검증은 여기서 먼저 돌리고 실기기로 확인한다.
// 그 순서가 유효하다는 것은 1-12 병합 실험에서 확인됐다(CLAUDE.md).

var failures = 0

@MainActor
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print("  \(ok ? "✓" : "✗") \(label)\(detail.isEmpty ? "" : "  — \(detail)")")
    if !ok { failures += 1 }
}

@main
struct StorageCheck {

    /// **컨테이너를 붙들어 둔다.** 처음에는 컨텍스트만 반환했는데 컨테이너가
    /// 해제되면서 첫 fetch 에서 죽었다. 하네스 버그였다.
    @MainActor static var containers: [ModelContainer] = []

    @MainActor
    static func makeContext(url: URL? = nil, allowsSave: Bool = true) throws -> ModelContext {
        let config = url.map { ModelConfiguration(url: $0, allowsSave: allowsSave) }
            ?? ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Session.self, Clip.self,
                                           configurations: config)
        containers.append(container)
        return container.mainContext
    }

    @MainActor
    static func count(_ context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<Session>()).count
    }

    /// 임시 루트. 실제 `~/Documents` 를 건드리지 않으려고 주입한다.
    static func makeRoot(_ tag: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "mellow-\(tag)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 녹화본 흉내. 내용은 상관없다 — `ClipStore` 는 파일을 옮기기만 한다.
    static func makeSource(_ dir: URL, _ name: String) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: name)
        FileManager.default.createFile(atPath: url.path,
                                       contents: Data(repeating: 0x41, count: 1024))
        return url
    }

    @MainActor
    static func main() async throws {
        setbuf(stdout, nil)
        try sessionStoreSuite()
        try clipStoreSuite()
        try await sessionCloseSuite()
        orientationSuite()
        recordingGateSuite()

        print("\n─────────────────────────────")
        print(failures == 0 ? "전부 통과" : "✗ 실패 \(failures)건")
        if failures > 0 { exit(1) }
    }

    // MARK: - 2-6 · 2-7  세션 생성과 이어가기

    @MainActor
    static func sessionStoreSuite() throws {
        let root = try makeRoot("sessionstore")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = SessionFileStore(documentsDirectory: root)
        // 9군이 `ClipStore.save` 를 거치므로 옮길 원본 파일이 필요하다.
        let scratch = root.appending(path: "tmp", directoryHint: .isDirectory)

        // ── 1. 빈 스토어에서 시작하면 새로 만든다
        print("\n1) 빈 스토어 — startOrResume")
        let a = try makeContext()
        let storeA = SessionStore(context: a, files: files)
        let start1 = try storeA.startOrResume()
        let s1 = start1.session
        check("새로 만든다", start1.isNew, s1.displayTitle)
        check("clips/ 까지 만들어진다",
              FileManager.default.fileExists(atPath: files.clipsDirectory(s1.id).path))
        check("생성 직후 방향은 미정", s1.orientationState == .unset)
        check("title 저장값은 빈 문자열", s1.title.isEmpty, "\"\(s1.title)\"")
        check("displayTitle 은 createdAt 에서 나온다",
              s1.displayTitle == Session.autoTitle(for: s1.createdAt), s1.displayTitle)

        // ── 2. 진행 중 세션이 있으면 이어간다
        print("\n2) 같은 스토어 — 다시 startOrResume")
        let start2 = try storeA.startOrResume(title: "버려질 제목")
        check("이어간다", !start2.isNew)
        check("같은 세션이다", start2.session.id == s1.id)
        check("넘긴 title 은 버린다", start2.session.title.isEmpty,
              "\"\(start2.session.title)\"")
        check("세션이 늘지 않았다", try count(a) == 1, "\(try count(a))개")

        // ── 3. 제목 처리
        print("\n3) 제목 처리")
        let b = try makeContext()
        let named = try SessionStore(context: b, files: files)
            .startOrResume(title: "  제주 3일  ").session
        check("앞뒤 공백을 다듬어 저장", named.title == "제주 3일", "\"\(named.title)\"")
        check("displayTitle 은 입력값 그대로", named.displayTitle == "제주 3일")

        let c = try makeContext()
        let blank = try SessionStore(context: c, files: files)
            .startOrResume(title: "   ").session
        check("공백만 준 것은 입력하지 않은 것", blank.title.isEmpty)
        check("그래서 날짜 이름이 나온다",
              blank.displayTitle == Session.autoTitle(for: blank.createdAt),
              blank.displayTitle)

        // ── 4. .missing 세션만 있으면 새로 만든다
        //
        // **여기서는 클립을 일부러 직접 삽입한다.** 9군과 반대다. 2-8 이후
        // `.missing` 은 정상 경로로 만들어지지 않으므로(`ClipStore.save` 를
        // 거치면 같은 저장 단위에서 방향이 붙는다), 손상 상태를 재현하려면
        // 저장 계층을 우회하는 수밖에 없다. 2-8 이전에 만들어져 기기에 남아
        // 있는 세션이 정확히 이 모양이다.
        print("\n4) .missing 세션만 있을 때 (손상 상태는 직접 삽입으로만 만들어진다)")
        let d = try makeContext()
        let storeD = SessionStore(context: d, files: files)
        let broken = try storeD.startOrResume().session
        d.insert(Clip(order: 0, fileName: "x.mov", duration: 9.9, session: broken))
        try d.save()
        check("상태가 .missing 이다", broken.orientationState == .missing)
        check("이어가기 후보가 아니다", !broken.isResumable)
        check("resumableSession 이 nil", try storeD.resumableSession() == nil)

        // 2-8. **`.missing` 세션에는 방향을 새로 붙이지 않는다.**
        //
        // **실기기로는 도달할 수 없는 분기라 여기가 유일한 검증 수단이다.**
        // `decideOrientation` 은 `ClipStore.save` 에 넘긴 세션에만 불리고, 그
        // 세션은 `startOrResume` 이 돌려준 것이며, `isResumable` 필터가
        // `.missing` 을 제외한다 — 앱 UI 로는 인자가 될 방법 자체가 없다.
        //
        // 실기기 검증에서 "손상 세션에 방향이 안 붙었다" 를 통과로 적었다가
        // 철회했다. **손대지 않은 세션이 안 변하는 것은 2-7 의 제외 동작이지
        // 2-8 의 가드가 아니다.** 가드를 실제로 때리는 것은 이 두 줄뿐이다.
        //
        // 막지 않으면 먼저 찍힌 클립과 계열이 다른 방향이 붙고, 계열 간
        // 혼재는 정규화로도 복구되지 않는다. 복구는 2-16 의 몫이다.
        check("`.missing` 에는 방향을 정하지 않는다",
              !broken.decideOrientation(.landscape))
        check("거절 후에도 .missing 그대로", broken.orientationState == .missing,
              "\(broken.orientationState)")

        // **`.corrupted` 는 같은 방식으로 못 덮는다.** 클립을 직접 삽입하면
        // `.missing` 이 되지만, `.corrupted` 는 `orientationRaw` 에
        // `Orientation` 으로 해석되지 않는 문자열이 들어가 있어야 한다.
        //
        // 그 문자열을 넣을 방법이 없다. `orientationRaw` 는 `private` 이고,
        // 쓰는 곳 셋이 전부 유효값만 넣는다 — `init` 은 `Orientation?`,
        // `decideOrientation` 은 `Orientation`, `undoOrientationDecision` 은
        // `nil` 이다. 하네스가 같은 모듈로 컴파일돼도 `private` 은 파일 밖에서
        // 안 뚫린다.
        //
        // 남은 수단은 스토어 SQLite 를 직접 열어 컬럼을 고치는 것뿐인데,
        // CoreData 의 `Z` 접두 스키마에 하네스를 묶게 된다. **할지 말지는
        // 2-16 에서 정한다** — 거기서 `.corrupted` 복구를 실제로 만들 때
        // 픽스처가 필요해지고, 그때 이 비용을 지불할 이유가 생긴다.
        //
        // 지금 덮이는 것은 `.missing`(위 두 줄)과 `.decided`(9군)뿐이다.

        let start4 = try storeD.startOrResume()
        check("새 세션을 만든다", start4.isNew)
        check("망가진 세션이 아니다", start4.session.id != broken.id)
        check("망가진 세션은 그대로 남는다", try count(d) == 2, "\(try count(d))개")
        check("남은 세션의 클립도 그대로", broken.clips.count == 1)
        check("새 세션은 이어갈 수 있다", start4.session.isResumable)

        // ── 5. 닫힌 세션은 이어가지 않는다
        print("\n5) 닫힌 세션")
        let e = try makeContext()
        let storeE = SessionStore(context: e, files: files)
        let closed = try storeE.startOrResume().session
        closed.isClosed = true
        try e.save()
        check("이어가기 불가", !closed.isResumable)
        check("새로 만든다", try storeE.startOrResume().isNew)
        check("닫힌 세션은 남는다", try count(e) == 2, "\(try count(e))개")

        // ── 6. 후보가 여럿이면 최신 하나 + 로그
        print("\n6) 후보가 여럿 (위에 [session] ⚠ 로그가 찍혀야 한다)")
        let f = try makeContext()
        let storeF = SessionStore(context: f, files: files)
        let old = Session(title: "오래된", createdAt: Date(timeIntervalSince1970: 1_000))
        let mid = Session(title: "중간", createdAt: Date(timeIntervalSince1970: 2_000))
        let new = Session(title: "최신", createdAt: Date(timeIntervalSince1970: 3_000))
        for s in [old, mid, new] { f.insert(s) }
        try f.save()
        let picked = try storeF.resumableSession()
        check("최신을 고른다", picked?.id == new.id, picked?.displayTitle ?? "nil")
        check("나머지를 건드리지 않는다", try count(f) == 3, "\(try count(f))개")
        check("나머지가 닫히지 않았다", !old.isClosed && !mid.isClosed)

        // ── 7. 디렉터리 실패 → 메타데이터가 생기지 않는다
        print("\n7) 디렉터리 생성 실패")
        let blockedRoot = try makeRoot("blocked")
        defer { try? FileManager.default.removeItem(at: blockedRoot) }
        let blockedFiles = SessionFileStore(documentsDirectory: blockedRoot)
        // sessions/ 자리에 디렉터리 대신 파일을 놓으면 createDirectory 가 실패한다.
        FileManager.default.createFile(atPath: blockedFiles.sessionsRoot.path,
                                       contents: Data("not a directory".utf8))
        let g = try makeContext()
        do {
            _ = try SessionStore(context: g, files: blockedFiles).startOrResume()
            check("실패해야 한다", false, "성공해버렸다")
        } catch let error as SessionStartError {
            if case .file = error {
                check("SessionStartError.file 로 분류", true)
            } else {
                check("SessionStartError.file 로 분류", false, "\(error)")
            }
        }
        check("메타데이터가 생기지 않았다", try count(g) == 0, "\(try count(g))개")

        // ── 8. save 실패 경로
        //
        // 파일 권한을 건드리는 방법은 통하지 않는다 — SQLite 가 이미 연 fd 로
        // 쓰기 때문이다. `allowsSave: false` 로 API 층에서 실패시킨다.
        print("\n8) save 실패 경로 (allowsSave: false)")
        let roRoot = try makeRoot("ro")
        defer { try? FileManager.default.removeItem(at: roRoot) }
        let roFiles = SessionFileStore(documentsDirectory: roRoot)
        let storeURL = roRoot.appending(path: "RO.store")
        // 없는 스토어는 읽기 전용으로 열지 못한다. 먼저 만들어 둔다.
        _ = try makeContext(url: storeURL)
        let ro = try makeContext(url: storeURL, allowsSave: false)
        let roStore = SessionStore(context: ro, files: roFiles)

        let dirsBefore = (try? roFiles.sessionIDs().count) ?? -1
        do {
            _ = try roStore.startOrResume()
            check("save 가 실패해야 한다", false, "성공해버렸다")
        } catch let error as SessionStartError {
            if case .metadata = error {
                check("SessionStartError.metadata 로 분류", true)
            } else {
                check("metadata 로 분류되어야 한다", false, "\(error)")
            }
        }
        let dirsAfter = (try? roFiles.sessionIDs().count) ?? -1
        check("디렉터리는 남는다 (고아, 2-16 대상)", dirsAfter == dirsBefore + 1,
              "\(dirsBefore) → \(dirsAfter)")

        let survivors = try ro.fetch(FetchDescriptor<Session>())
        let fresh = try makeContext(url: storeURL)
        let onDisk = try fresh.fetch(FetchDescriptor<Session>())
        check("스토어에는 들어가지 않았다", onDisk.isEmpty, "\(onDisk.count)개")
        check("컨텍스트에도 유령이 남지 않는다 (rollback + 재조회 delete)",
              survivors.isEmpty, "\(survivors.count)개")

        // ── 9. 첫 클립이 방향을 정하고, 이어가기가 유지된다 (2-8)
        //
        // **이 군은 반드시 `ClipStore.save` 를 거쳐야 한다.** 예전에는
        // `i.insert(Clip(...))` 로 클립을 직접 넣었는데, 그러면 `alsoApply` 를
        // 타지 않아 **2-8 구현이 아무리 옳아도 결과가 `.missing` 그대로였다.**
        // 방향 확정은 `ClipStore.save` 의 저장 단위 안에서만 일어나므로,
        // 클립을 넣는 경로가 실사용과 같아야 이 군이 무엇이든 검증한다.
        // 직접 삽입으로 되돌리면 이 검증이 **조용히 무력해진다.**
        //
        // 2-7 이 `.missing` 을 이어가기 후보에서 제외하는데 방향을 쓰는 코드가
        // 없던 동안에는 모든 세션이 클립 하나에 `.missing` 이 되어 F-01 AC 가
        // 깨졌다("탭할 때마다 세션이 새로 생긴다"). 아래 네 줄이 그것이
        // 닫혔는지를 본다.
        print("\n9) 2-8 — 첫 클립이 방향을 정하고 이어가기가 유지된다")
        let i = try makeContext()
        let storeI = SessionStore(context: i, files: files)
        let clipsI = ClipStore(context: i, files: files)
        let live = try storeI.startOrResume().session
        check("클립 0개일 때는 이어갈 수 있다", live.isResumable)
        check("실제로 이어간다", !(try storeI.startOrResume().isNew))

        // 실사용 호출부(`ContentView.saveLastClipToActiveSession`)와 같은 모양이다.
        var decided = false
        _ = try clipsI.save(clipAt: try makeSource(scratch, "s9-first.mov"),
                            duration: 9.9,
                            to: live,
                            alsoApply: { decided = $0.decideOrientation(.portrait) },
                            revertOnFailure: { if decided { $0.undoOrientationDecision() } })

        check("첫 클립이 방향을 정한다 (decideOrientation == true)", decided)
        check("클립이 하나 들어가면 .decided 다",
              live.orientationState == .decided(.portrait), "\(live.orientationState)")
        check("그래서 계속 이어갈 수 있다", live.isResumable)
        check("세션이 새로 생기지 않는다 — F-01 AC",
              !(try storeI.startOrResume().isNew))
        check("세션이 1개 그대로", try count(i) == 1, "\(try count(i))개")

        // 두 번째 클립은 방향을 **다시 정하지 않는다.** `false` 가 정상이며
        // 실패가 아니다. 여기에 반대 계열을 넣어 보는 이유는, 가드가 없으면
        // 한 세션에 세로·가로가 섞이기 때문이다 (계열 간은 정규화로도 복구 불가).
        var decidedAgain = false
        _ = try clipsI.save(clipAt: try makeSource(scratch, "s9-second.mov"),
                            duration: 9.9,
                            to: live,
                            alsoApply: { decidedAgain = $0.decideOrientation(.landscape) },
                            revertOnFailure: { if decidedAgain { $0.undoOrientationDecision() } })

        check("두 번째 클립은 방향을 정하지 않는다 (false 가 정상)", !decidedAgain)
        check("방향이 첫 클립 것으로 유지된다",
              live.orientationState == .decided(.portrait), "\(live.orientationState)")
        check("클립 2컷", live.clips.count == 2, "\(live.clips.count)컷")
    }

    // MARK: - 2-4 · 2-5  클립 저장과 삭제

    @MainActor
    static func clipStoreSuite() throws {
        let root = try makeRoot("clipstore")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = SessionFileStore(documentsDirectory: root)
        let scratch = root.appending(path: "tmp", directoryHint: .isDirectory)

        // ══ A. 유령 조사 — save() 실패 시 Clip 이 남는가
        //
        // `SessionStore` 보다 축이 둘 더 있다. 관계(`session.clips`)와
        // `orientationState` 다. 관계에 남으면 `orderedClips` 를 타고 병합
        // 대상이 오염되고, `.unset` 이 `.missing` 으로 바뀌면 2-7 의 이어가기
        // 판정까지 오염된다.
        print("\nA) ClipStore.save 실패 (allowsSave: false)")
        let storeURL = root.appending(path: "A.store")
        let writable = try makeContext(url: storeURL)
        let seededID = try SessionStore(context: writable, files: files)
            .startOrResume().session.id

        let ro = try makeContext(url: storeURL, allowsSave: false)
        guard let session = try ro.fetch(FetchDescriptor<Session>())
            .first(where: { $0.id == seededID }) else {
            check("읽기 전용 컨텍스트에서 세션을 찾는다", false)
            return
        }
        check("사전 상태: 클립 0개", session.clips.isEmpty)
        check("사전 상태: 방향 .unset", session.orientationState == .unset)

        let source = try makeSource(scratch, "rec-1.mov")
        var thrown: Error?
        do {
            _ = try ClipStore(context: ro, files: files)
                .save(clipAt: source, duration: 9.9, to: session)
            check("save 가 실패해야 한다", false, "성공해버렸다")
        } catch {
            thrown = error
        }
        if let e = thrown as? ClipSaveError, case .metadata = e {
            check("ClipSaveError.metadata 로 분류", true)
        } else {
            check("ClipSaveError.metadata 로 분류", false, "\(String(describing: thrown))")
        }

        // 2-5 리뷰의 계약 — 녹화본을 지우지 않고 되돌린다
        check("원본이 제자리로 되돌아왔다",
              FileManager.default.fileExists(atPath: source.path))
        let leftovers = (try? files.clipFileNames(in: seededID)) ?? []
        check("세션 디렉터리에 남은 파일이 없다", leftovers.isEmpty, "\(leftovers)")

        let sameCtx = try ro.fetch(FetchDescriptor<Clip>()).count
        let fresh = try makeContext(url: storeURL)
        let onDisk = try fresh.fetch(FetchDescriptor<Clip>()).count
        check("스토어에는 들어가지 않았다", onDisk == 0, "\(onDisk)개")
        check("컨텍스트에 유령 Clip 이 없다", sameCtx == 0, "\(sameCtx)개")
        check("관계(session.clips)에 유령이 없다", session.clips.isEmpty,
              "\(session.clips.count)개")
        check("orderedClips 에 유령이 없다 — 병합 대상 오염",
              session.orderedClips.isEmpty, "\(session.orderedClips.count)개")
        check("orientationState 가 .unset 그대로 — 2-7 판정 오염",
              session.orientationState == .unset, "\(session.orientationState)")
        check("이어가기 가능이 유지된다", session.isResumable)

        // ══ B. 2-4 회귀 — 정상 저장
        //
        // **`alsoApply` 를 반드시 넘긴다 (2-10 에서 고쳤다).** 예전에는 넘기지
        // 않고 저장했는데, 그러면 클립이 쌓여도 방향이 붙지 않아 이 세션이
        // **`.missing`** 이 된다 — 2-8 이 "정상 경로로는 만들어지지 않는다" 고
        // 한 상태를 저장 계층을 거치고도 하네스가 만들고 있었다. 파라미터가
        // 옵셔널이라 안 넘겨도 조용히 통과한다.
        //
        // **그 여파는 C군에서 터진다.** 방향이 없는 세션은 클립을 전부 지워도
        // `.unset` 이 되므로, 2-10 이 있든 없든 결과가 같아 회귀를 물지 못한다.
        // 2-8 이 9군을 `ClipStore.save` 경유로 고친 것과 같은 종류의 구멍이다.
        print("\nB) 2-4 회귀 — 정상 저장 (2-8 경유)")
        let b = try makeContext()
        let bs = try SessionStore(context: b, files: files).startOrResume().session
        let clips = ClipStore(context: b, files: files)

        var saved: [Clip] = []
        for i in 0..<4 {
            let src = try makeSource(scratch, "b-\(i).mov")
            var decided = false
            let clip = try clips.save(
                clipAt: src,
                duration: 9.9 + Double(i) / 100,
                to: bs,
                alsoApply: { decided = $0.decideOrientation(.portrait) },
                revertOnFailure: { if decided { $0.undoOrientationDecision() } })
            saved.append(clip)
            check("order=\(i) 로 붙는다", clip.order == i, "order=\(clip.order)")
            check("첫 클립만 방향을 정한다", decided == (i == 0), "decided=\(decided)")
            check("원본이 사라진다 (이동)",
                  !FileManager.default.fileExists(atPath: src.path))
            check("목적지에 있다",
                  FileManager.default.fileExists(
                    atPath: files.clipURL(fileName: clip.fileName, in: bs.id).path))
        }
        check("파일명이 클립 id 다",
              saved.allSatisfy { $0.fileName == "\($0.id.uuidString).mov" })
        let onDiskCount = try files.clipFileNames(in: bs.id).count
        check("메타 4컷 / 파일 4개", bs.clips.count == 4 && onDiskCount == 4,
              "메타 \(bs.clips.count) / 파일 \(onDiskCount)")
        // C군이 회귀를 물려면 여기서 방향이 실제로 붙어 있어야 한다.
        check("★ 세션 방향이 .decided(portrait) — C군의 전제",
              bs.orientationState == .decided(.portrait), "\(bs.orientationState)")

        // ══ C. 2-5 회귀 — 삭제와 재정렬, 그리고 2-10 방향 초기화
        print("\nC) 2-5 회귀 — 삭제와 재정렬 / 2-10 방향 초기화")
        let middle = bs.orderedClips[2]
        let middleName = middle.fileName
        let result = try clips.delete(middle)
        check("남은 3컷", result.remainingCount == 3, "\(result.remainingCount)")
        check("파일을 지웠다", result.fileRemoved)
        check("비지 않았다", !result.sessionBecameEmpty)
        check("order 가 0,1,2 로 재정렬", bs.orderedClips.map(\.order) == [0, 1, 2],
              "\(bs.orderedClips.map(\.order))")
        let afterDelete = try files.clipFileNames(in: bs.id)
        check("지운 파일이 실제로 없다", !afterDelete.contains(middleName))
        check("파일명은 개명되지 않았다",
              Set(bs.orderedClips.map(\.fileName)) == Set(afterDelete))

        let lastResult = try clips.delete(bs.orderedClips.last!)
        check("마지막 컷 삭제 후 2컷", lastResult.remainingCount == 2)
        check("order 가 0,1", bs.orderedClips.map(\.order) == [0, 1],
              "\(bs.orderedClips.map(\.order))")

        // 마지막 한 컷을 남기기 전까지는 방향이 그대로여야 한다. 0개가 되는
        // 순간에만 초기화되는 것이 2-10 이고, 그 전에 지워지면 다음 촬영이
        // 남아 있는 클립과 다른 계열로 방향을 다시 정할 수 있다.
        check("아직 방향이 유지된다 (2컷 남음)",
              bs.orientationState == .decided(.portrait), "\(bs.orientationState)")

        var becameEmpty = false
        for clip in bs.orderedClips {
            becameEmpty = try clips.delete(clip).sessionBecameEmpty
        }
        check("클립 0개", bs.clips.isEmpty, "\(bs.clips.count)개")
        check("sessionBecameEmpty 가 선다", becameEmpty)
        // ★ 2-10 이 없으면 여기서 .decided(portrait) 가 그대로 나온다.
        check("★ 2-10 — 클립 0개가 되면 방향이 .unset 으로 돌아온다",
              bs.orientationState == .unset, "\(bs.orientationState)")
        check("이어가기 후보로 남는다", bs.isResumable)

        // ══ D. 2-8 회귀 — 저장 실패 시 세션 방향이 되돌아간다
        //
        // **A 군이 커버하지 않는 경로다.** A 는 `alsoApply` 를 넘기지 않고
        // 부른 것이라 되돌릴 세션 변경이 애초에 없었다. 방향을 세팅한 채
        // 실패시켜야 `revertOnFailure` 가 도는지 알 수 있다.
        //
        // **왜 이 회귀가 중요한가.** 클립 삽입은 `insert` 라 롤백 후 유령이
        // 남고, 방향은 `update` 라 롤백해도 인메모리에 새 값이 그대로 남는다.
        // 걷어내지 않으면 스토어는 "방향 없음 · 클립 없음" 인데 인메모리는
        // **"방향 있음 · 클립 없음"** 이 된다. `orientationState` 가
        // `.decided` 라 다음 촬영이 방향을 이미 정해진 것으로 읽고, 2-9 가
        // 들어오면 클립이 하나도 없는 세션에서 녹화가 막힌다.
        //
        // **스토어에는 흔적이 없어 2-16 이 이 어긋남을 영영 검출하지 못한다.**
        // 그래서 규율이 아니라 코드로 막고, 그 코드가 사는지를 여기서 본다.
        print("\nD) 2-8 회귀 — 저장 실패 시 방향 되돌리기 (allowsSave: false)")
        let dURL = root.appending(path: "D.store")
        let dWritable = try makeContext(url: dURL)
        let dSeededID = try SessionStore(context: dWritable, files: files)
            .startOrResume().session.id

        let dro = try makeContext(url: dURL, allowsSave: false)
        guard let dSession = try dro.fetch(FetchDescriptor<Session>())
            .first(where: { $0.id == dSeededID }) else {
            check("읽기 전용 컨텍스트에서 세션을 찾는다", false)
            return
        }
        check("사전 상태: 방향 .unset", dSession.orientationState == .unset)

        let dSource = try makeSource(scratch, "rec-d.mov")
        var dDecided = false
        var dThrown: Error?
        do {
            _ = try ClipStore(context: dro, files: files)
                .save(clipAt: dSource,
                      duration: 9.9,
                      to: dSession,
                      alsoApply: { dDecided = $0.decideOrientation(.landscape) },
                      revertOnFailure: { if dDecided { $0.undoOrientationDecision() } })
            check("save 가 실패해야 한다", false, "성공해버렸다")
        } catch {
            dThrown = error
        }
        check("alsoApply 가 실제로 방향을 정했다 — 되돌릴 것이 있다", dDecided)
        if let e = dThrown as? ClipSaveError, case .metadata = e {
            check("ClipSaveError.metadata 로 분류", true)
        } else {
            check("ClipSaveError.metadata 로 분류", false, "\(String(describing: dThrown))")
        }
        // ★ revert 가 없으면 여기서 .decided(landscape) 가 나온다.
        check("★ 인메모리 방향이 .unset 으로 돌아온다",
              dSession.orientationState == .unset, "\(dSession.orientationState)")
        check("클립 관계가 0개", dSession.clips.isEmpty, "\(dSession.clips.count)개")
        let dFresh = try makeContext(url: dURL)
        let dOnDisk = try dFresh.fetch(FetchDescriptor<Clip>()).count
        check("재조회한 스토어에도 클립 0개", dOnDisk == 0, "\(dOnDisk)개")
        check("원본이 release 로 되돌아왔다",
              FileManager.default.fileExists(atPath: dSource.path))
        let dLeftovers = (try? files.clipFileNames(in: dSeededID)) ?? []
        check("세션 디렉터리에 남은 파일이 없다", dLeftovers.isEmpty, "\(dLeftovers)")

        // 되돌린 뒤에도 세션이 멀쩡한지. 방향이 `.unset` 이고 클립이 0개이므로
        // 다음 촬영이 방향을 다시 정할 수 있어야 한다 — 2-7 의 이어가기 후보다.
        check("이어가기 가능이 유지된다", dSession.isResumable)

        // ══ G. 2-10 회귀 — 삭제가 실패했을 때 인메모리 복원
        //
        // **D군의 거울상이다.** D는 저장 실패 시 *새로 정한* 방향을 걷어내고,
        // G는 삭제 실패 시 *지운* 방향을 되살린다. 둘 다 `rollback()` 이
        // 스토어만 되돌리기 때문에 필요한 코드다.
        //
        // **복원하지 않으면 `.missing` 이 만들어진다** (하네스 실측). raw 는
        // `nil` 인데 삭제된 클립이 관계에 되살아나기 때문이다. 2-16 이
        // "`.missing` 은 2-8 이후 도달 불가" 라고 적은 전제에 **'2-10 을
        // 올바로 만들었을 때'** 라는 단서가 붙는 이유가 이것이다.
        //
        // **`order` 복원은 2-5 결함 수정이다. 2-10 이 아니다.** 삭제 실패 후
        // 재번호가 인메모리에 남아 되살아난 클립과 겹치는 것은 2-10 과 무관하게
        // 이미 있던 것이고, 오염원이 같은 `catch` 라 같은 자리에서 고칠 뿐이다.
        print("\nG) 2-10 회귀 — 삭제 실패 시 인메모리 복원 (allowsSave: false)")

        // ── G-1. 마지막 컷 삭제 실패 → 방향이 되살아나는가
        let gURL = root.appending(path: "G.store")
        let gWritable = try makeContext(url: gURL)
        let gSession = try SessionStore(context: gWritable, files: files)
            .startOrResume().session
        let gStore = ClipStore(context: gWritable, files: files)
        var gDecided = false
        _ = try gStore.save(clipAt: try makeSource(scratch, "g-0.mov"),
                            duration: 9.9, to: gSession,
                            alsoApply: { gDecided = $0.decideOrientation(.portrait) },
                            revertOnFailure: { if gDecided { $0.undoOrientationDecision() } })
        let gSeededID = gSession.id
        check("사전: 방향 .decided(portrait) · 1컷",
              gSession.orientationState == .decided(.portrait) && gSession.clips.count == 1,
              "\(gSession.orientationState) / \(gSession.clips.count)컷")

        let gro = try makeContext(url: gURL, allowsSave: false)
        guard let g = try gro.fetch(FetchDescriptor<Session>())
            .first(where: { $0.id == gSeededID }) else {
            check("읽기 전용 컨텍스트에서 세션을 찾는다", false)
            return
        }
        var gThrown: Error?
        do { _ = try ClipStore(context: gro, files: files).delete(g.orderedClips[0]) }
        catch { gThrown = error }
        if let e = gThrown as? ClipDeleteError, case .metadata = e {
            check("ClipDeleteError.metadata 로 분류", true)
        } else {
            check("ClipDeleteError.metadata 로 분류", false, "\(String(describing: gThrown))")
        }
        // ★ 복원이 없으면 여기서 .missing 이 나온다.
        check("★ 방향이 .decided(portrait) 로 되살아난다",
              g.orientationState == .decided(.portrait), "\(g.orientationState)")
        check("`.missing` 이 만들어지지 않았다", g.orientationState != .missing)
        check("2-7 이 이어가기 후보에서 빼지 않는다", g.isResumable)
        check("2-9 가 읽는 orientation 이 살아 있다", g.orientation == .portrait,
              "\(String(describing: g.orientation))")
        check("클립이 되살아나 있다 (삭제가 없던 일이 됐다)", g.clips.count == 1,
              "\(g.clips.count)컷")
        let gOnDisk = try makeContext(url: gURL).fetch(FetchDescriptor<Clip>()).count
        check("스토어도 온전하다", gOnDisk == 1, "\(gOnDisk)개")
        let gFiles = (try? files.clipFileNames(in: gSeededID)) ?? []
        check("파일도 그대로다", gFiles.count == 1, "\(gFiles.count)개")

        // ── G-2. 가운데 컷 삭제 실패 → order 에 중복이 남지 않는가 (2-5 결함)
        //
        // **가운데여야 한다.** 마지막 컷은 재번호가 애초에 돌지 않아
        // (`each.order != index` 가 전부 거짓) 이 결함이 드러나지 않는다.
        let hURL = root.appending(path: "H.store")
        let hWritable = try makeContext(url: hURL)
        let hSession = try SessionStore(context: hWritable, files: files)
            .startOrResume().session
        let hStore = ClipStore(context: hWritable, files: files)
        for i in 0..<3 {
            var hDecided = false
            _ = try hStore.save(clipAt: try makeSource(scratch, "h-\(i).mov"),
                                duration: 9.9, to: hSession,
                                alsoApply: { hDecided = $0.decideOrientation(.portrait) },
                                revertOnFailure: { if hDecided { $0.undoOrientationDecision() } })
        }
        let hSeededID = hSession.id

        let hro = try makeContext(url: hURL, allowsSave: false)
        guard let h = try hro.fetch(FetchDescriptor<Session>())
            .first(where: { $0.id == hSeededID }) else {
            check("읽기 전용 컨텍스트에서 세션을 찾는다", false)
            return
        }
        check("사전: order 가 0,1,2", h.orderedClips.map(\.order) == [0, 1, 2],
              "\(h.orderedClips.map(\.order))")
        _ = try? ClipStore(context: hro, files: files).delete(h.orderedClips[1])

        // ★ 복원이 없으면 여기서 [0, 1, 1] 이 나온다 — 중복이다.
        //
        // **`fetch` 를 돌리기 전에 읽어야 한다.** 같은 컨텍스트에서 그 타입을
        // 다시 조회하면 스토어 값으로 복원되어 결함이 가려진다(실측). 삭제
        // 실패 직후 곧바로 읽는 호출부가 실제로 보는 값이 이것이다.
        let hOrders = h.orderedClips.map(\.order)
        check("★ order 에 중복이 없다 (2-5 결함 수정)",
              Set(hOrders).count == hOrders.count, "\(hOrders)")
        check("order 가 0,1,2 로 되돌아왔다", hOrders == [0, 1, 2], "\(hOrders)")
        check("방향은 건드리지 않았다 (0개가 아니므로)",
              h.orientationState == .decided(.portrait), "\(h.orientationState)")
        let hOnDisk = try makeContext(url: hURL)
            .fetch(FetchDescriptor<Clip>()).map(\.order).sorted()
        check("스토어의 order 도 0,1,2", hOnDisk == [0, 1, 2], "\(hOnDisk)")

        // ── G-3. `.corrupted` 세션은 클립 0개가 되어도 불변인가 — **확인 불가**
        //
        // 억지로 만들지 않는다. `orientationRaw` 가 `private` 이고 쓰는 곳
        // 넷이 전부 유효값이나 `nil` 만 넣어서(`init` · `decideOrientation` ·
        // `undoOrientationDecision` · `resetOrientation`) 해석 불가 문자열을
        // 넣을 방법이 없다. 스토어 SQLite 를 직접 고치는 수밖에 없는데
        // CoreData 의 `Z` 접두 스키마에 하네스를 묶는 비용이다.
        //
        // **`.corrupted` 를 건드리지 않기로 한 것이 확정이 아니라 유보인 이유가
        // 이것이다** — 어느 쪽을 골라도 검증할 수단이 없다. 2-16 에서
        // `.corrupted` 복구를 만들 때 함께 정한다 (Tasks.md 2-10 · 2-16).
        print("  · `.corrupted` + 클립 0개 — **확인 불가.** 만들 수단이 없다 (2-16 에서 정한다)")

        // ══ H. 2-12 — 세션 삭제
        //
        // **`.cascade` 는 선언이지 관측이 아니었다.** 이 프로젝트는 SwiftData
        // 선언 동작이 예상과 다른 것을 세 번 밟았다(`#Predicate` enum 미지원 ·
        // `transaction` 이 롤백하지 않음 · `rollback()` 이 insert 를 인메모리에
        // 남김). 2-12 본문이 "클립을 하나씩 지울 필요가 없다" 를 전제로 삼으므로
        // 여기서 값으로 고정한다.
        print("\nH) 2-12 — 세션 삭제와 cascade")

        // ── H-1. 정상 삭제
        let iURL = root.appending(path: "I.store")
        let iCtx = try makeContext(url: iURL)
        let iSession = try SessionStore(context: iCtx, files: files).startOrResume().session
        let iStore = ClipStore(context: iCtx, files: files)
        for n in 0..<2 {
            var d = false
            _ = try iStore.save(clipAt: try makeSource(scratch, "i-\(n).mov"),
                                duration: 9.9, to: iSession,
                                alsoApply: { d = $0.decideOrientation(.portrait) },
                                revertOnFailure: { if d { $0.undoOrientationDecision() } })
        }
        let iID = iSession.id
        check("사전: 세션 1 · 클립 2 · 파일 2",
              iSession.clips.count == 2
              && ((try? files.clipFileNames(in: iID))?.count ?? 0) == 2)

        let iResult = try SessionStore(context: iCtx, files: files).delete(iSession)
        check("디렉터리를 지웠다 (directoryRemoved)", iResult.directoryRemoved)
        check("디렉터리가 실제로 없다",
              !FileManager.default.fileExists(atPath: files.sessionDirectory(iID).path))

        let iSameS = try iCtx.fetch(FetchDescriptor<Session>()).count
        let iSameC = try iCtx.fetch(FetchDescriptor<Clip>()).count
        check("같은 컨텍스트에 세션 유령이 없다", iSameS == 0, "\(iSameS)개")
        check("★ 같은 컨텍스트에 클립 유령이 없다 — cascade", iSameC == 0, "\(iSameC)개")

        let iFresh = try makeContext(url: iURL)
        let iDiskS = try iFresh.fetch(FetchDescriptor<Session>()).count
        let iDiskC = try iFresh.fetch(FetchDescriptor<Clip>()).count
        check("스토어에 세션 0개", iDiskS == 0, "\(iDiskS)개")
        check("★ 스토어에 클립 0개 — cascade 가 실제로 돈다", iDiskC == 0, "\(iDiskC)개")

        // ── H-2. 관계를 fault in 하지 않고 삭제해도 cascade 가 도는가
        //
        // **실사용이 이 모양이다.** 목록에서 세션을 골라 지울 때 `clips` 를
        // 읽었다는 보장이 없다. 관계가 fault 상태면 cascade 가 대상을 모를
        // 수 있으므로 따로 본다.
        let jURL = root.appending(path: "J.store")
        let jCtx = try makeContext(url: jURL)
        let jSession = try SessionStore(context: jCtx, files: files).startOrResume().session
        let jStore = ClipStore(context: jCtx, files: files)
        for n in 0..<3 {
            var d = false
            _ = try jStore.save(clipAt: try makeSource(scratch, "j-\(n).mov"),
                                duration: 9.9, to: jSession,
                                alsoApply: { d = $0.decideOrientation(.portrait) },
                                revertOnFailure: { if d { $0.undoOrientationDecision() } })
        }
        let jID = jSession.id

        // 새 컨텍스트로 다시 열어 관계를 한 번도 건드리지 않은 인스턴스를 얻는다.
        let jCold = try makeContext(url: jURL)
        guard let jFetched = try jCold.fetch(FetchDescriptor<Session>())
            .first(where: { $0.id == jID }) else {
            check("차가운 컨텍스트에서 세션을 찾는다", false)
            return
        }
        // `.clips` 를 읽지 않고 그대로 넘긴다.
        _ = try SessionStore(context: jCold, files: files).delete(jFetched)
        let jDiskC = try makeContext(url: jURL).fetch(FetchDescriptor<Clip>()).count
        check("★ 관계를 안 읽어도 cascade 가 돈다", jDiskC == 0, "\(jDiskC)개")

        // ── H-3. 이미 없는 디렉터리 — 실패가 아니다
        let kURL = root.appending(path: "K.store")
        let kCtx = try makeContext(url: kURL)
        let kSession = try SessionStore(context: kCtx, files: files).startOrResume().session
        let kID = kSession.id
        _ = try files.removeSessionDirectory(kID)      // 미리 지워 둔다
        let kResult = try SessionStore(context: kCtx, files: files).delete(kSession)
        check("이미 없으면 directoryRemoved = false — 실패가 아니다",
              !kResult.directoryRemoved)
        check("메타데이터는 지워졌다",
              (try makeContext(url: kURL).fetch(FetchDescriptor<Session>()).count) == 0)

        // ── H-4. ⚠ 삭제 실패 후 **첫 조회가 거짓말한다** (알려진 동작)
        //
        // 2-12 가 인메모리를 되돌리지 않기로 한 근거가 "2회차부터 저절로
        // 맞는다" 이다. **그 근거 자체를 회귀로 박는다** — 이것이 바뀌면
        // 2-12 항목과 코드 주석의 서술이 통째로 틀려진다.
        //
        // 2-10 의 stale 과 성질이 다르다. 그쪽은 `fetch` 를 아무리 돌려도
        // 안 고쳐져 명시적 복원이 필요했다.
        print("\nH-4) 2-12 — 삭제 실패 후 첫 조회 vs 두 번째 조회 (allowsSave: false)")
        let lURL = root.appending(path: "L.store")
        let lCtx = try makeContext(url: lURL)
        let lSession = try SessionStore(context: lCtx, files: files).startOrResume().session
        let lStore = ClipStore(context: lCtx, files: files)
        for n in 0..<2 {
            var d = false
            _ = try lStore.save(clipAt: try makeSource(scratch, "l-\(n).mov"),
                                duration: 9.9, to: lSession,
                                alsoApply: { d = $0.decideOrientation(.portrait) },
                                revertOnFailure: { if d { $0.undoOrientationDecision() } })
        }
        let lID = lSession.id

        let lro = try makeContext(url: lURL, allowsSave: false)
        guard let l = try lro.fetch(FetchDescriptor<Session>())
            .first(where: { $0.id == lID }) else {
            check("읽기 전용 컨텍스트에서 세션을 찾는다", false)
            return
        }
        var lThrown: Error?
        do { _ = try SessionStore(context: lro, files: files).delete(l) }
        catch { lThrown = error }
        if let e = lThrown as? SessionDeleteError, case .metadata = e {
            check("SessionDeleteError.metadata 로 분류", true)
        } else {
            check("SessionDeleteError.metadata 로 분류", false, "\(String(describing: lThrown))")
        }

        let first = try lro.fetch(FetchDescriptor<Session>()).count
        let second = try lro.fetch(FetchDescriptor<Session>()).count
        check("★ 첫 조회는 0개 — 화면에서 사라진다 (알려진 동작)",
              first == 0, "\(first)개")
        check("★ 두 번째 조회는 1개 — 저절로 맞는다. 그래서 되돌리지 않는다",
              second == 1, "\(second)개")
        let lClips = try lro.fetch(FetchDescriptor<Clip>()).count
        check("클립은 그 사이에도 살아 있다", lClips == 2, "\(lClips)개")
        check("보유 참조가 isDeleted 가 아니다", !l.isDeleted)

        let lFresh = try makeContext(url: lURL)
        let lDiskS = try lFresh.fetch(FetchDescriptor<Session>()).count
        let lDiskC = try lFresh.fetch(FetchDescriptor<Clip>()).count
        check("스토어는 온전하다 (세션 1 · 클립 2)",
              lDiskS == 1 && lDiskC == 2, "세션 \(lDiskS) / 클립 \(lDiskC)")
        check("★ 디렉터리를 안 건드렸다 — 메타 먼저의 값어치",
              FileManager.default.fileExists(atPath: files.sessionDirectory(lID).path))
        let lFiles = (try? files.clipFileNames(in: lID))?.count ?? 0
        check("클립 파일도 그대로다", lFiles == 2, "\(lFiles)개")
    }

    // MARK: - 2-12a  세션 닫기

    /// 스텁 파이프라인. 받은 URL 을 기록하고 지정된 대로 성공/실패한다.
    ///
    /// **호출 기록이 검증의 절반이다.** "이미 닫힌 세션에 재호출해도
    /// 무해하다" 는 파이프라인이 다시 불리지 않았다는 것이고(완성본 중복
    /// 없음), "가드에 걸리면 무변화" 는 아예 불리지 않았다는 것이다.
    /// 던졌다/안 던졌다만 보면 그 둘이 안 보인다.
    final class StubPipeline {
        struct Failure: Error {}
        var calls: [[URL]] = []
        var shouldFail = false

        // 격리하지 않는다. `close` 가 메인 액터에서 부르고 하네스도 전부
        // 메인 액터라 경합이 없다 — 언어 모드 5 기준이다.
        var closure: ([URL]) async throws -> Void {
            { urls in
                self.calls.append(urls)
                if self.shouldFail { throw Failure() }
            }
        }
    }

    /// `close` 검증 (2-12a). 전 케이스 스텁 파이프라인으로 돈다 —
    /// 실제 병합·익스포트·사진 저장은 실기기 게이트의 몫이다.
    @MainActor
    static func sessionCloseSuite() async throws {
        let root = try makeRoot("close")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = SessionFileStore(documentsDirectory: root)
        let scratch = root.appending(path: "tmp", directoryHint: .isDirectory)

        /// 픽스처는 실사용 경로로 만든다 — `ClipStore.save` 를 타서 방향이
        /// `.decided` 가 되는 것까지가 픽스처의 일이다 (B군 ★ 방식. 직접
        /// 삽입으로 만들면 `.missing` 이 되어 검증이 조용히 무력해진다).
        func seedSession(_ context: ModelContext, clips: Int, tag: String) throws -> Session {
            let session = try SessionStore(context: context, files: files)
                .startOrResume().session
            let store = ClipStore(context: context, files: files)
            for n in 0..<clips {
                var decided = false
                _ = try store.save(clipAt: try makeSource(scratch, "\(tag)-\(n).mov"),
                                   duration: 9.9, to: session,
                                   alsoApply: { decided = $0.decideOrientation(.portrait) },
                                   revertOnFailure: { if decided { $0.undoOrientationDecision() } })
            }
            if clips > 0 {
                check("★ 픽스처: 방향 .decided(portrait) — 실사용 경로를 탔다",
                      session.orientationState == .decided(.portrait),
                      "\(session.orientationState)")
            }
            return session
        }

        // ══ N-1. 가드 — 클립 0개 (= `.unset`. 정의상 0컷 세션이 곧 `.unset` 이다)
        print("\nN-1) 2-12a — 닫기 가드: 클립 0개 (.unset)")
        let a = try makeContext()
        let emptySession = try seedSession(a, clips: 0, tag: "n1")
        check("픽스처: .unset · 0컷",
              emptySession.orientationState == .unset && emptySession.clips.isEmpty)
        let stubA = StubPipeline()
        var aThrown: Error?
        do {
            try await SessionStore(context: a, files: files, pipeline: stubA.closure)
                .close(emptySession)
        } catch { aThrown = error }
        if let e = aThrown as? SessionCloseError, case .empty = e {
            check("SessionCloseError.empty 로 던진다", true)
        } else {
            check("SessionCloseError.empty 로 던진다", false,
                  "\(String(describing: aThrown))")
        }
        check("isClosed == false 그대로", !emptySession.isClosed)
        check("파이프라인이 불리지 않았다", stubA.calls.isEmpty,
              "\(stubA.calls.count)회")

        // ══ N-2. 가드 — `.missing`
        //
        // 손상 상태는 직접 삽입으로만 만들어진다 (sessionStoreSuite 4군과
        // 같은 수단). `.corrupted` 는 그 수단으로도 못 만든다 — G-3 과 같은
        // 제약이며, 가드가 `.decided` 를 요구하는 형태라 분기는 같다.
        print("\nN-2) 2-12a — 닫기 가드: .missing")
        let b = try makeContext()
        let broken = try SessionStore(context: b, files: files).startOrResume().session
        b.insert(Clip(order: 0, fileName: "x.mov", duration: 9.9, session: broken))
        try b.save()
        check("픽스처: .missing", broken.orientationState == .missing,
              "\(broken.orientationState)")
        let stubB = StubPipeline()
        var bThrown: Error?
        do {
            try await SessionStore(context: b, files: files, pipeline: stubB.closure)
                .close(broken)
        } catch { bThrown = error }
        if let e = bThrown as? SessionCloseError, case .orientationUnresolved = e {
            check("SessionCloseError.orientationUnresolved 로 던진다", true)
        } else {
            check("SessionCloseError.orientationUnresolved 로 던진다", false,
                  "\(String(describing: bThrown))")
        }
        check("isClosed == false 그대로", !broken.isClosed)
        check("파이프라인이 불리지 않았다", stubB.calls.isEmpty)
        print("  · `.corrupted` 가드 — **확인 불가.** 상태를 만들 수단이 없다"
              + " (G-3 과 같은 제약. 가드는 `.decided` 요구라 분기는 `.missing` 과 같다)")

        // ══ N-3. 정상 닫기 (스텁 성공)
        print("\nN-3) 2-12a — 정상 닫기")
        let cURL = root.appending(path: "N3.store")
        let c = try makeContext(url: cURL)
        let live = try seedSession(c, clips: 2, tag: "n3")
        let stubC = StubPipeline()
        try await SessionStore(context: c, files: files, pipeline: stubC.closure).close(live)

        check("파이프라인이 한 번 불렸다", stubC.calls.count == 1,
              "\(stubC.calls.count)회")
        let expected = live.orderedClips.map {
            files.clipURL(fileName: $0.fileName, in: live.id)
        }
        check("★ 넘어간 URL 이 저장 계층 조합과 일치한다 — order 순",
              stubC.calls.first == expected)
        check("그 URL 에 파일이 실제로 있다",
              expected.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        check("★ isClosed == true (인메모리)", live.isClosed)
        let cFresh = try makeContext(url: cURL).fetch(FetchDescriptor<Session>())
        check("★ 재조회로도 닫혀 있다", cFresh.first?.isClosed == true)
        check("이어가기 불가가 된다", !live.isResumable)
        check("다음 startOrResume 은 새로 만든다",
              try SessionStore(context: c, files: files).startOrResume().isNew)

        // 재호출 — 무해. 던지지 않고, 파이프라인이 다시 불리지 않는다
        // (완성본 중복이 생기지 않는다).
        var reThrown: Error?
        do {
            try await SessionStore(context: c, files: files, pipeline: stubC.closure)
                .close(live)
        } catch { reThrown = error }
        check("★ 닫힌 세션에 재호출 — 던지지 않는다", reThrown == nil,
              "\(String(describing: reThrown))")
        check("★ 파이프라인이 다시 불리지 않았다", stubC.calls.count == 1,
              "\(stubC.calls.count)회")
        check("상태 불변 (isClosed == true)", live.isClosed)

        // ══ N-4. 파이프라인 실패 — 세션 무변화
        print("\nN-4) 2-12a — 파이프라인 실패")
        let dURL = root.appending(path: "N4.store")
        let d = try makeContext(url: dURL)
        let dSession = try seedSession(d, clips: 2, tag: "n4")
        let stubD = StubPipeline()
        stubD.shouldFail = true
        var dThrown: Error?
        do {
            try await SessionStore(context: d, files: files, pipeline: stubD.closure)
                .close(dSession)
        } catch { dThrown = error }
        if let e = dThrown as? SessionCloseError, case .pipeline = e {
            check("SessionCloseError.pipeline 로 분류", true)
        } else {
            check("SessionCloseError.pipeline 로 분류", false,
                  "\(String(describing: dThrown))")
        }
        check("★ 열린 채 남는다 (isClosed == false)", !dSession.isClosed)
        check("클립 2컷 그대로", dSession.clips.count == 2, "\(dSession.clips.count)컷")
        check("방향 유지", dSession.orientationState == .decided(.portrait),
              "\(dSession.orientationState)")
        check("이어가기 가능 유지", dSession.isResumable)
        check("파일도 그대로", ((try? files.clipFileNames(in: dSession.id))?.count ?? 0) == 2)
        let dFresh = try makeContext(url: dURL).fetch(FetchDescriptor<Session>())
        check("재조회로도 열려 있다", dFresh.first?.isClosed == false)

        // ══ N-5. 파이프라인 성공 + `isClosed` 기록 실패 (allowsSave: false)
        //
        // **사진 앱에는 완성본이 있는데 세션은 열린 채인 케이스다** — AC 가
        // 허용으로 확정한 상태. 되돌림이 없으면 스토어는 "열림" 인데
        // 인메모리가 "닫힘" 이 되어 화면과 가드가 거짓 세션을 본다.
        print("\nN-5) 2-12a — 기록 실패 시 되돌림 (allowsSave: false)")
        let eURL = root.appending(path: "N5.store")
        let eWritable = try makeContext(url: eURL)
        let eSeeded = try seedSession(eWritable, clips: 1, tag: "n5")
        let eID = eSeeded.id

        let ero = try makeContext(url: eURL, allowsSave: false)
        guard let eSession = try ero.fetch(FetchDescriptor<Session>())
            .first(where: { $0.id == eID }) else {
            check("읽기 전용 컨텍스트에서 세션을 찾는다", false)
            return
        }
        let stubE = StubPipeline()
        var eThrown: Error?
        do {
            try await SessionStore(context: ero, files: files, pipeline: stubE.closure)
                .close(eSession)
        } catch { eThrown = error }
        if let e = eThrown as? SessionCloseError, case .metadata = e {
            check("SessionCloseError.metadata 로 분류", true)
        } else {
            check("SessionCloseError.metadata 로 분류", false,
                  "\(String(describing: eThrown))")
        }
        check("파이프라인은 돌았다 — 사진 앱에 완성본이 남는 케이스",
              stubE.calls.count == 1, "\(stubE.calls.count)회")
        // ★ 되돌림이 없으면 여기서 true 가 나온다 (update 는 rollback 이
        //   인메모리를 되돌리지 않는다).
        check("★ isClosed 가 false 로 되돌아왔다 (인메모리)", !eSession.isClosed)
        let eFresh = try makeContext(url: eURL).fetch(FetchDescriptor<Session>())
        check("★ 재조회한 스토어도 열려 있다", eFresh.first?.isClosed == false)
        check("이어가기 후보로 남는다", eSession.isResumable)

        // ══ N-6. 닫힌 세션 읽기 전용 가드 (ClipStore)
        //
        // N-3 이 닫아 둔 세션을 그대로 쓴다.
        print("\nN-6) 2-12a — 닫힌 세션의 클립 추가·삭제 가드")
        let mSource = try makeSource(scratch, "n6-blocked.mov")
        var mSaveThrown: Error?
        do {
            _ = try ClipStore(context: c, files: files)
                .save(clipAt: mSource, duration: 9.9, to: live)
        } catch { mSaveThrown = error }
        if let e = mSaveThrown as? ClipSaveError, case .sessionClosed = e {
            check("★ save → ClipSaveError.sessionClosed", true)
        } else {
            check("★ save → ClipSaveError.sessionClosed", false,
                  "\(String(describing: mSaveThrown))")
        }
        check("파일이 옮겨지지 않았다 — 원본 제자리 (가드가 adopt 앞)",
              FileManager.default.fileExists(atPath: mSource.path))
        check("세션 디렉터리에 새 파일이 없다",
              ((try? files.clipFileNames(in: live.id))?.count ?? -1) == 2)
        check("메타 2컷 그대로", live.clips.count == 2, "\(live.clips.count)컷")

        var mDeleteThrown: Error?
        do {
            _ = try ClipStore(context: c, files: files).delete(live.orderedClips[0])
        } catch { mDeleteThrown = error }
        if let e = mDeleteThrown as? ClipDeleteError, case .sessionClosed = e {
            check("★ delete → ClipDeleteError.sessionClosed", true)
        } else {
            check("★ delete → ClipDeleteError.sessionClosed", false,
                  "\(String(describing: mDeleteThrown))")
        }
        check("클립 2컷 그대로", live.clips.count == 2, "\(live.clips.count)컷")
        check("파일 2개 그대로",
              ((try? files.clipFileNames(in: live.id))?.count ?? -1) == 2)

        // 세션 삭제는 가드 대상이 아니다 — 닫힌 세션도 삭제 가능이 확정
        // 계약이다 (PRD F-07 AC). 사진 앱의 완성본은 우리 소유가 아니라
        // 건드리지 않는다(스텁이라 여기서는 관측 대상이 없다).
        let closedDeletion = try SessionStore(context: c, files: files).delete(live)
        check("★ 닫힌 세션 삭제는 된다 — 가드 미적용", closedDeletion.directoryRemoved)
        let cAfter = try c.fetch(FetchDescriptor<Session>()).count
        check("남은 세션 1개 (N-3 의 startOrResume 이 만든 것)", cAfter == 1,
              "\(cAfter)개")
        let cClips = try c.fetch(FetchDescriptor<Clip>()).count
        check("cascade 도 그대로 돈다 — 클립 0개", cClips == 0, "\(cClips)개")
    }

    // MARK: - 2-8  방향 도출 (VideoTrackSpec)

    /// `preferredTransform` 과 `naturalSize` 로 세션 방향을 판정한다.
    ///
    /// **파일 없이 값만 넣어 확인한다.** 판정이 순수 계산이라 촬영도 I/O 도
    /// 필요 없다 — 그 점이 이 프로퍼티를 `VideoTrackSpec` 에 둔 이유이기도 하다.
    ///
    /// 케이스는 CLAUDE.md "실측 preferredTransform" 표 그대로다 (iPhone 12).
    /// **계열 내 180도 쌍이 같은 결과를 내는지가 핵심이다** — 세로(90)와
    /// 거꾸로(270)가 둘 다 `.portrait`, 가로L(0)과 가로R(180)이 둘 다
    /// `.landscape` 여야 한다. 좌우 차이는 2-D 의 정규화가 흡수하므로
    /// `Orientation` 이 2값으로 충분하다는 전제가 여기에 걸려 있다.
    @MainActor
    static func orientationSuite() {
        print("\nE) 2-8 — preferredTransform 에서 방향 도출 (실측표 4케이스)")

        /// 방향 판정에 쓰이는 두 값만 실제 값으로 채운다. 나머지는 판정에
        /// 관여하지 않으므로 그럴듯한 값이면 된다.
        func track(_ size: CGSize, _ transform: CGAffineTransform) -> VideoTrackSpec {
            VideoTrackSpec(naturalSize: size,
                           preferredTransform: transform,
                           codec: nil,
                           nominalFrameRate: 30,
                           minFrameDuration: CMTime(value: 20, timescale: 600),
                           duration: CMTime(value: 5980, timescale: 600))
        }

        let hd = CGSize(width: 1920, height: 1080)

        // CLAUDE.md 실측표. 네 방향 모두 naturalSize 는 1920×1080 이고
        // 회전은 transform 이 들고 있다.
        let portrait = track(hd, CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0))
        let upsideDown = track(hd, CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1920))
        let landscapeL = track(hd, CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0))
        let landscapeR = track(hd, CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1920, ty: 1080))

        check("세로(capture 90) → portrait", portrait.orientation == .portrait,
              "\(String(describing: portrait.orientation))")
        check("거꾸로(capture 270) → portrait", upsideDown.orientation == .portrait,
              "\(String(describing: upsideDown.orientation))")
        check("가로L(capture 0) → landscape", landscapeL.orientation == .landscape,
              "\(String(describing: landscapeL.orientation))")
        check("가로R(capture 180) → landscape", landscapeR.orientation == .landscape,
              "\(String(describing: landscapeR.orientation))")

        // 계열 내 180도 쌍. 위 네 줄과 중복처럼 보이지만 **보는 것이 다르다** —
        // 위는 각 값이 맞는지를, 여기는 쌍이 서로 같은지를 본다. 판정이
        // 각도별로 갈리기 시작하면 여기가 먼저 깨진다.
        check("★ 세로 계열 180도 쌍이 같은 결과",
              portrait.orientation == upsideDown.orientation)
        check("★ 가로 계열 180도 쌍이 같은 결과",
              landscapeL.orientation == landscapeR.orientation)
        check("계열끼리는 다르다", portrait.orientation != landscapeL.orientation)

        // 렌더 규격으로 판정한다는 것은, 회전이 폭·높이를 실제로 맞바꾼다는 뜻이다.
        let rendered = hd.applying(portrait.preferredTransform)
        check("세로 클립의 렌더 규격이 1080×1920",
              abs(rendered.width) == 1080 && abs(rendered.height) == 1920,
              "\(abs(rendered.width))×\(abs(rendered.height))")

        // 정사각은 판정 불가다. 한쪽으로 임의로 붙이면 판정 불가가 조용히
        // 정상값으로 둔갑하고, 2-8 은 그것을 방향으로 확정해 버린다.
        let square = track(CGSize(width: 1080, height: 1080), .identity)
        check("정사각은 nil — 임의로 한쪽에 붙이지 않는다", square.orientation == nil,
              "\(String(describing: square.orientation))")

        // 세로로 찍힌 파일을 세로 세션에 넣는 실사용 조합. 2-8 호출부가
        // 하는 일이 이 한 줄이다.
        let session = Session(title: "")
        check("도출값으로 방향을 정할 수 있다",
              portrait.orientation.map { session.decideOrientation($0) } == true)
        check("세션이 .decided(portrait) 가 된다",
              session.orientationState == .decided(.portrait),
              "\(session.orientationState)")
    }

    // MARK: - 2-9  방향 불일치 차단 (RecordingGate)

    /// 세션 방향과 기기 계열을 대조하는 판정.
    ///
    /// **이 군이 돌 수 있는 이유가 `RecordingGate` 가 UIKit 을 모르기
    /// 때문이다.** 판정 소스는 `UIDevice.current.orientation` 이지만
    /// (2-9 (A)) 그 타입을 판정 함수까지 들이지 않고 **계열에서 잘랐다** —
    /// `UIDeviceOrientation` 을 인자로 받게 만들었으면 여기서 못 돈다
    /// (macOS 에 UIKit 이 없다. 실측: `no such module 'UIKit'`).
    ///
    /// 잘라낸 쪽(`UIDeviceOrientation.family`)에는 우리 로직이 없다 —
    /// UIKit 의 `isPortrait` / `isLandscape` 를 그대로 부르는 세 줄이라
    /// 검증할 것이 없고, 판단은 전부 이쪽에 있다.
    @MainActor
    static func recordingGateSuite() {
        print("\nF) 2-9 — 방향 불일치 차단 판정")

        func decide(_ session: Session.OrientationState,
                    _ device: Orientation?) -> RecordingGate.Decision {
            RecordingGate.decide(session: session, device: device)
        }

        // ── 지시된 네 경우
        check("세로 세션 + 기기 세로 → 통과",
              decide(.decided(.portrait), .portrait) == .allowed)
        check("세로 세션 + 기기 가로 → 차단",
              decide(.decided(.portrait), .landscape) == .blocked(required: .portrait),
              "\(decide(.decided(.portrait), .landscape))")
        check("세로 세션 + 계열 없음 → 통과 (2-9 (B))",
              decide(.decided(.portrait), nil) == .allowed)
        check("미정 세션 + 기기 가로 → 통과 (첫 클립이 정한다)",
              decide(.unset, .landscape) == .allowed)

        // ── 반대 계열도 대칭인지. 한쪽만 맞으면 판정이 방향에 치우친 것이다
        check("가로 세션 + 기기 가로 → 통과",
              decide(.decided(.landscape), .landscape) == .allowed)
        check("가로 세션 + 기기 세로 → 차단",
              decide(.decided(.landscape), .portrait) == .blocked(required: .landscape),
              "\(decide(.decided(.landscape), .portrait))")

        // ── 차단이 **맞춰야 할 방향**을 들고 있어야 안내 문구를 만들 수 있다
        check("차단은 세션 방향을 실어 보낸다",
              decide(.decided(.portrait), .landscape).required == .portrait)
        check("통과는 실어 보낼 것이 없다",
              decide(.decided(.portrait), .portrait).required == nil)

        // ── 도달 불가 경로. 분기를 만들지 않았다는 것을 고정한다
        //
        // `.missing` / `.corrupted` 세션은 `isResumable` 필터에 걸려 촬영
        // 화면의 활성 세션이 될 수 없다(2-8 에서 확인). 여기서 통과가 나오는
        // 것은 **특별 처리를 만들지 않았다는 뜻**이며, 만약 이 경로가 실제로
        // 열린다면 고칠 곳은 판정이 아니라 2-7 의 필터다.
        check("`.missing` 은 통과 — 특별 처리를 만들지 않았다",
              decide(.missing, .landscape) == .allowed)
        check("`.corrupted` 도 통과",
              decide(.corrupted(rawValue: "portrai"), .landscape) == .allowed)

        // ── 계열 내 180도는 애초에 구분되지 않는다
        //
        // 세로/거꾸로가 둘 다 `.portrait` 로 접혀 들어오므로 이 판정은 그
        // 차이를 볼 수단이 없다. **없는 것이 맞다** — 막으면 로우앵글
        // 촬영이 막힌다. 접히는 것 자체는 E군이 transform 으로 확인한다.
        check("계열 내 180도는 판정에 들어오지 않는다 (E군과 짝)",
              decide(.decided(.portrait), .portrait) == .allowed)
    }
}
