#if DEBUG

import Foundation
import SwiftData

// 2-A 실기기 검증용 콘솔 로그. **계측 장치이지 기능이 아니다.**
//
// 저장 계층(2-1~2-5)은 전부 Mac 하네스로만 확인했고 실기기에서
// "녹화 → 저장 → 앱 재실행" 을 한 번도 돌리지 않았다. 그 왕복을 콘솔에서
// 확인하려면 저장 경로와 order 부여가 stdout 에 보여야 하는데, 프로브
// 버튼들은 화면의 `probeNote` 에만 남기고 있었다.
//
// 저장 계층 코드에는 넣지 않는다 — `ClipStore` / `SessionFileStore` 는
// 실패할 때만 말한다는 성질을 유지한다. 여기는 3-13 에서 프로브 UI 와
// 함께 통째로 사라지는 자리다.
//
// # 릴리스에서 빠진다 (Codex 리뷰 ③)
//
// 파일 경로와 세션 id 를 stdout 에 뿌리는 계측이라 `#if DEBUG` 로 감싼다.
// **파일 전체를 감싼다.** `CaptureTrace` 는 `isEnabled` 한 줄만 감싸서 타입이
// Release 이진에 그대로 남는다 — 이쪽은 심볼도 로그 문자열도 0건이다
// (2-A 에서 이진 확인. CLAUDE.md "계측 코드와 릴리스 빌드" 참고).
// **호출부도 함께 감싼다** — 빈 구현을 남기면 릴리스에서 아무것도 하지 않는
// 버튼이 화면에 남는다.
//
// 범위는 여기까지다. `ContentView` 의 프로브·측정 버튼은 감싸지 않는다.
// 그 화면은 프리뷰·디버그 오버레이·측정 동선까지 통째로 임시이고 3-3 에서
// 실제 촬영 화면으로 교체된다. 일부만 조건부 컴파일로 감싸면 나머지가
// 프로덕션용이라는 잘못된 신호를 남기고, 3-13 에서 걷어낼 것만 늘어난다.
//
// # 메인 컨텍스트 전용 (Codex 리뷰 ④)
//
// `Session` / `Clip` 관계를 직접 fault-in 하므로 SwiftData 의 메인 컨텍스트
// 전용 원칙(CLAUDE.md)이 여기에도 걸린다. `ClipStore` 와 같은 표시를 달아
// 다른 호출부가 생겨도 컴파일러가 막게 한다.
@MainActor
enum StoreProbeLog {

    private static let files = SessionFileStore.shared

    /// 디렉터리 열거 결과. **"비어 있음" 과 "못 셌음" 을 구분한다** (Codex 리뷰 ②).
    ///
    /// 둘을 같은 빈 배열로 접으면 권한·I/O 실패가 "파일 0개" 로 보이고,
    /// 고아 대조가 아무것도 못 찾은 것처럼 나온다. 양방향 대조가 이 로그의
    /// 판정 근거인 이상 실패는 실패라고 말해야 한다.
    private enum Listing {
        case ok([String])
        case failed(Error)

        /// 대조에 쓸 목록. 실패면 비어 있지만, **그 상태로 결론을 내리면 안 된다.**
        var names: [String] {
            switch self {
            case .ok(let names): return names
            case .failed: return []
            }
        }

        /// 개수 자리에 그대로 넣을 수 있는 표시.
        var summary: String {
            switch self {
            case .ok(let names): return "파일 \(names.count)개"
            case .failed(let error): return "⚠ 파일 목록 실패 — \(error)"
            }
        }

        var succeeded: Bool {
            if case .ok = self { return true }
            return false
        }
    }

    // MARK: - 재실행 직후 재고 조사

    /// 스토어와 파일시스템을 나란히 찍는다. **게이트 2의 첫 항목**
    /// ("앱을 강제 종료했다 켜도 세션과 클립이 그대로 남아 있다") 이
    /// 성립했는지 이 출력 하나로 판정한다.
    ///
    /// 메타데이터와 파일을 양방향으로 대조한다 — 메타데이터에만 있는 것과
    /// 파일에만 있는 것 둘 다 드러나야 2-16 이 치울 대상이 보인다.
    static func inventory(_ sessions: [Session], label: String) {
        print("[probe] ═══ 재고 조사 — \(label)")

        let storeURL = MellowModelContainer.storeURL
        print("[probe] store     \(storeURL.path)")
        print("[probe]           \(exists(storeURL) ? "있음 \(size(of: storeURL))" : "없음")")

        let root = files.sessionsRoot
        print("[probe] sessions  \(root.path)")
        print("[probe]           \(exists(root) ? "있음" : "없음")"
              + "  백업제외=\(describeBackupExclusion(root))")

        print("[probe] 세션 \(sessions.count)개 (스토어 기준)")
        for session in sessions {
            let directory = files.sessionDirectory(session.id)
            let onDisk = listClipFiles(in: session.id)
            print("[probe]  · \(session.displayTitle)  id=\(session.id.uuidString)")
            print("[probe]    디렉터리=\(exists(directory) ? "있음" : "없음")"
                  + "  방향=\(describe(session.orientationState))"
                  + "  메타 \(session.clips.count)컷 / \(onDisk.summary)"
                  + "  이어가기=\(session.isResumable ? "가능" : "불가")")

            var accounted = Set<String>()
            for clip in session.orderedClips {
                let url = files.clipURL(fileName: clip.fileName, in: session.id)
                accounted.insert(clip.fileName)
                print(String(format: "[probe]      order=%d  %.3fs  %@  파일=%@",
                             clip.order, clip.duration, clip.fileName,
                             exists(url) ? size(of: url) : "✕ 없음"))
            }

            // 메타데이터에 없는 파일. 저장 실패 경로가 남긴 고아이며 2-16 대상이다.
            //
            // **열거에 실패했으면 이 대조를 아예 하지 않는다.** 빈 목록으로
            // 훑으면 "고아 없음" 이라는 결론이 조용히 만들어진다.
            if onDisk.succeeded {
                for orphan in onDisk.names where !accounted.contains(orphan) {
                    let url = files.clipURL(fileName: orphan, in: session.id)
                    print("[probe]      ⚠ 고아 파일  \(orphan)  \(size(of: url))")
                }
            } else {
                print("[probe]      ⚠ 고아 파일 대조 건너뜀 — 목록을 읽지 못했다")
            }
        }

        // 메타데이터에 없는 세션 디렉터리.
        let known = Set(sessions.map(\.id))
        do {
            for id in try files.sessionIDs() where !known.contains(id) {
                print("[probe]  ⚠ 고아 세션 디렉터리  \(id.uuidString)")
            }
        } catch {
            print("[probe]  ⚠ 세션 디렉터리 목록 실패 — \(error)")
        }

        temporaryLeftovers()
        print("[probe] ═══")
    }

    /// `tmp/` 에 남은 녹화본. 저장이 **이동**이면 옮긴 파일은 여기 없어야 한다.
    static func temporaryLeftovers() {
        let tmp = FileManager.default.temporaryDirectory
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: tmp.path)
                .filter { $0.hasPrefix("mellow-") }
                .sorted()
        } catch {
            print("[probe] ⚠ tmp 목록 실패 — \(error)")
            return
        }

        guard !names.isEmpty else {
            print("[probe] tmp 남은 녹화본 없음")
            return
        }
        // Phase 1 실험 잔여물이 100개 넘게 쌓여 있다. 전부 찍으면 로그를 덮으므로
        // 개수만 본다. 방금 저장한 클립이 tmp 에서 사라졌는지는 `savedClip` 이
        // 해당 URL 하나를 직접 확인한다 — 그쪽이 판정 근거다.
        print("[probe] tmp 남은 녹화본 \(names.count)개  \(tmp.path)")
        guard names.count <= 10 else {
            print("[probe]   (10개 초과 — 목록 생략. Phase 1 잔여물)")
            return
        }
        for name in names {
            print("[probe]   \(name)  \(size(of: tmp.appending(path: name)))")
        }
    }

    // MARK: - 버튼별 흔적

    /// 세션 시작 결과 (2-6·2-7).
    ///
    /// **새로 만든 것과 이어간 것이 구분돼 보여야 한다.** 2-7 의 확인이
    /// 정확히 그 구분이기 때문이다.
    static func started(_ start: SessionStore.Start) {
        let session = start.session
        print("[probe] \(start.isNew ? "+ 새 세션" : "▶ 이어가기")"
              + "  \(session.displayTitle)  id=\(session.id.uuidString)")
        print("[probe]   제목저장값=\"\(session.title)\""
              + "  방향=\(describe(session.orientationState))"
              + "  \(session.clips.count)컷")
        print("[probe]   디렉터리 \(files.sessionDirectory(session.id).path)")
        print("[probe]   clips/ 있음=\(exists(files.clipsDirectory(session.id)))"
              + "  백업제외=\(describeBackupExclusion(files.sessionsRoot))")
    }

    static func savedClip(_ clip: Clip, in session: Session, from source: URL) {
        let destination = files.clipURL(fileName: clip.fileName, in: session.id)
        print(String(format: "[probe] ■ 클립 저장  order=%d  %.3fs", clip.order, clip.duration))
        print("[probe]   원본 \(source.path)")
        print("[probe]        → \(exists(source) ? "⚠ 아직 있음 (이동이 아니라 복사?)" : "사라짐 ✓")")
        print("[probe]   목적 \(destination.path)")
        print("[probe]        → \(exists(destination) ? "있음 \(size(of: destination))" : "⚠ 없음")")
        print("[probe]   세션 \(session.displayTitle) 의 order 목록 = "
              + session.orderedClips.map { "\($0.order)" }.joined(separator: ","))
    }

    /// 삭제 결과.
    ///
    /// # 관계에서 읽은 `order` 는 교차 검증한다 (Codex 리뷰 ①)
    ///
    /// `ClipStore.delete` 는 **삭제 후의 `session.clips` 를 믿지 않는다.**
    /// 삭제 전에 남길 클립을 스냅샷해 두고 그것으로 재번호를 매긴다. 관계가
    /// 언제 갱신되는지에 기대지 않기 위해서다.
    ///
    /// 그런데 이 로그는 직후에 `session.orderedClips` 를 다시 읽는다.
    /// **관계 읽기를 없애지 않는 이유는 그 값이 맞는지가 확인 대상이기
    /// 때문이다** — 2-5 재정렬이 화면에 보이는 순서와 일치하는지를 보는
    /// 자리다. 대신 `ClipStore` 가 실제로 쓴 결과(`remainingCount`)와
    /// 대조하고, 어긋나면 조용히 지나가지 않게 `⚠` 를 붙인다.
    ///
    /// 개수뿐 아니라 `0..<n` 연속인지도 본다. 개수만 맞고 값이 중복되면
    /// 정렬이 모호해져 완성본의 컷 순서가 흔들린다 — 2-4 가 `order` 를
    /// 개수가 아니라 최대값+1 로 매기는 이유가 그것이다.
    static func deletedClip(fileName: String,
                            in session: Session,
                            result: ClipStore.Deletion) {
        let url = files.clipURL(fileName: fileName, in: session.id)
        print("[probe] ⌫ 클립 삭제  \(fileName)")
        print("[probe]   파일 \(result.fileRemoved ? "지움" : "이미 없었음")"
              + "  실제 확인=\(exists(url) ? "⚠ 아직 있음" : "없음 ✓")")
        print("[probe]   남은 \(result.remainingCount)컷"
              + (result.sessionBecameEmpty ? "  · 비었음(2-10 대상)" : ""))

        let orders = session.orderedClips.map(\.order)
        var problems: [String] = []
        if orders.count != result.remainingCount {
            problems.append("개수 불일치 — 관계 \(orders.count) vs 저장 \(result.remainingCount)")
        }
        if orders != Array(0..<orders.count) {
            problems.append("0..<\(orders.count) 연속이 아님")
        }

        let list = orders.map(String.init).joined(separator: ",")
        print("[probe]   재정렬 후 order 목록 = \(list.isEmpty ? "(없음)" : list)"
              + (problems.isEmpty ? "  ✓ 저장 결과와 일치"
                 : "  ⚠ " + problems.joined(separator: " · ")))
    }

    static func failure(_ label: String, _ error: Error) {
        print("[probe] ✕ \(label) — \(error)")
    }

    // MARK: - 자가시험

    /// 교차 검증이 실제로 어긋남을 잡는지 본다 (Codex 리뷰 ① 확인용).
    ///
    /// 실행 인자 `-MellowProbeSelfTest` 가 있을 때만 돈다. **스토어를 건드리지
    /// 않는다** — 실제 `deletedClip` 에 일부러 틀린 `Deletion` 을 먹여 출력만
    /// 본다. 어긋난 상태를 실기기에서 진짜로 만들려면 `ClipStore` 를 고쳐야
    /// 하는데 그건 이번 범위 밖이다.
    ///
    /// 삭제가 실제로 일어나지 않았으므로 "파일 실제 확인" 줄은 의미가 없다.
    /// 보는 것은 마지막 줄의 `✓` / `⚠` 뿐이다.
    static func selfTest(_ sessions: [Session]) {
        guard ProcessInfo.processInfo.arguments.contains("-MellowProbeSelfTest") else { return }
        print("[probe] ═══ 교차 검증 자가시험 — 스토어를 바꾸지 않는다")

        guard let session = sessions.first else {
            print("[probe] 건너뜀 — 세션이 없다")
            print("[probe] ═══")
            return
        }

        let actual = session.orderedClips.count
        print("[probe] ── 1) 저장 결과와 일치하는 입력 (remainingCount=\(actual))")
        deletedClip(fileName: "SELFTEST-일치.mov",
                    in: session,
                    result: .init(remainingCount: actual, fileRemoved: true))

        print("[probe] ── 2) 개수가 어긋나는 입력 (remainingCount=\(actual + 1))")
        deletedClip(fileName: "SELFTEST-불일치.mov",
                    in: session,
                    result: .init(remainingCount: actual + 1, fileRemoved: true))

        print("[probe] ═══")
    }

    // MARK: - 표시

    private static func listClipFiles(in id: UUID) -> Listing {
        do {
            return .ok(try files.clipFileNames(in: id))
        } catch {
            return .failed(error)
        }
    }

    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private static func size(of url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if bytes >= 1_048_576 {
            return String(format: "%.1fMB", Double(bytes) / 1_048_576)
        }
        return "\(bytes)B"
    }

    /// `isExcludedFromBackup` 실측. 2-3 은 macOS 에서만 확인했다.
    private static func describeBackupExclusion(_ url: URL) -> String {
        guard exists(url) else { return "—(디렉터리 없음)" }
        guard let value = try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]) else {
            return "읽기 실패"
        }
        return "\(value.isExcludedFromBackup.map(String.init(describing:)) ?? "nil")"
    }

    private static func describe(_ state: Session.OrientationState) -> String {
        switch state {
        case .unset: return "미정"
        case .missing: return "없음(손상)"
        case .decided(let orientation): return orientation.rawValue
        case .corrupted(let raw): return "손상(\(raw))"
        }
    }
}

#endif
