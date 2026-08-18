import Foundation
import SwiftData
import CoreMedia
import CoreGraphics

// 저장 계층 확인 하네스 (2-4 · 2-5 · 2-6 · 2-7 · 2-8).
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
//   swiftc -parse-as-library \
//     Mellow/Models/Orientation.swift \
//     Mellow/Models/Session.swift \
//     Mellow/Models/Clip.swift \
//     Mellow/Storage/SessionFileStore.swift \
//     Mellow/Storage/SessionStore.swift \
//     Mellow/Storage/ClipStore.swift \
//     Mellow/Diagnostics/ClipSpec.swift \
//     Tools/StorageCheck.swift -o /tmp/storagecheck && /tmp/storagecheck
//
// `ClipSpec.swift` 가 2-8 에서 들어왔다. 방향 도출(E군)이 그 파일의
// `VideoTrackSpec.orientation` 을 검증한다. UIKit 비의존이라 Mac 에서
// 그대로 컴파일된다 — 그 제약을 지키는 이유가 이것이다.
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
    static func main() throws {
        setbuf(stdout, nil)
        try sessionStoreSuite()
        try clipStoreSuite()
        orientationSuite()

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
        print("\nB) 2-4 회귀 — 정상 저장")
        let b = try makeContext()
        let bs = try SessionStore(context: b, files: files).startOrResume().session
        let clips = ClipStore(context: b, files: files)

        var saved: [Clip] = []
        for i in 0..<4 {
            let src = try makeSource(scratch, "b-\(i).mov")
            let clip = try clips.save(clipAt: src, duration: 9.9 + Double(i) / 100, to: bs)
            saved.append(clip)
            check("order=\(i) 로 붙는다", clip.order == i, "order=\(clip.order)")
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

        // ══ C. 2-5 회귀 — 삭제와 재정렬
        print("\nC) 2-5 회귀 — 삭제와 재정렬")
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

        var becameEmpty = false
        for clip in bs.orderedClips {
            becameEmpty = try clips.delete(clip).sessionBecameEmpty
        }
        check("클립 0개", bs.clips.isEmpty, "\(bs.clips.count)개")
        check("sessionBecameEmpty 가 선다 (2-10 대상)", becameEmpty)

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
}
