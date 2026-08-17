import Foundation
import SwiftData

// 저장 계층 확인 하네스 (2-4 · 2-5 · 2-6 · 2-7).
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
//     Tools/StorageCheck.swift -o /tmp/storagecheck && /tmp/storagecheck
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
        print("\n4) .missing 세션만 있을 때")
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

        // ── 9. 2-8 이 없으면 클립 하나로 이어가기가 끊긴다
        //
        // **고치지 않고 넘긴 문제를 실행 결과로 남긴다.** 방향을 쓰는 코드가
        // 없어(`ClipStore.save` 의 `alsoApply` 호출부 0) 클립이 들어가는 순간
        // 세션이 `.missing` 이 되고 F-01 AC 가 깨진다.
        //
        // **2-8 이 들어오면 아래 네 줄의 기대값이 뒤집혀야 한다.** 그때 2-8 이
        // 이 문제를 닫았다고 말할 수 있다.
        print("\n9) 2-8 미착수 상태 — 클립 하나로 이어가기가 끊긴다")
        let i = try makeContext()
        let storeI = SessionStore(context: i, files: files)
        let live = try storeI.startOrResume().session
        check("클립 0개일 때는 이어갈 수 있다", live.isResumable)
        check("실제로 이어간다", !(try storeI.startOrResume().isNew))

        i.insert(Clip(order: 0, fileName: "z.mov", duration: 9.9, session: live))
        try i.save()
        check("클립이 하나 들어가면 .missing 이 된다", live.orientationState == .missing)
        check("그래서 이어갈 수 없게 된다", !live.isResumable)
        check("⚠ 세션이 새로 생긴다 — F-01 AC 가 깨진다",
              try storeI.startOrResume().isNew)
        check("세션이 2개가 됐다", try count(i) == 2, "\(try count(i))개")
        print("     ↑ 2-8(방향 확정)이 들어오면 이 네 줄의 기대값이 뒤집혀야 한다")
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
    }
}
