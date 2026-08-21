import Foundation
import SwiftData

// 세션 생성과 이어가기 (2-6 · 2-7).
//
// `ClipStore` 와 대칭이다. 세션 생성이 파일시스템(디렉터리)과 SwiftData
// (메타데이터) 양쪽을 한 단위로 건드리므로 성격이 저장 계층이고, 2-12(세션
// 삭제)와 2-12a(세션 닫기)도 나중에 이 타입으로 온다.
//
// 메인 컨텍스트 전용이다 (CLAUDE.md "SwiftData 사용 원칙").

/// 세션을 시작하지 못한 이유. **호출부가 구분해야 하는 것만 케이스로 둔다.**
enum SessionStartError: Error, CustomStringConvertible {
    /// 이어갈 세션이 있는지 조회하지 못했다. **아무것도 만들지 않았다.**
    ///
    /// 조회 실패를 "이어갈 세션 없음" 으로 접으면 안 된다 — 그러면 이미 있는
    /// 세션을 못 보고 새로 만들어, F-01 AC("진행 중 세션이 이미 있으면 새로
    /// 만들지 않는다")를 조용히 어긴다.
    case query(underlying: Error)

    /// 세션 디렉터리를 만들지 못했다. **메타데이터는 만들어지지 않았다.**
    /// `.file(.outOfSpace)` 를 2-14 가 구분해서 쓴다.
    case file(SessionFileError)

    /// 디렉터리는 만들었는데 메타데이터를 쓰지 못했다.
    ///
    /// **디렉터리는 지우지 않는다.** 빈 디렉터리 하나가 고아로 남고 2-16 이
    /// 치운다. `ClipStore` 가 실패 시 녹화본을 원래 자리로 되돌리는 것과
    /// 다른데, 그쪽은 되돌릴 데이터가 있고 여기는 없기 때문이다 — 빈
    /// 디렉터리는 잃을 것이 없다.
    case metadata(underlying: Error)

    var description: String {
        switch self {
        case .query(let underlying):
            return "진행 중인 세션을 확인하지 못했습니다 — \(underlying)"
        case .file(let error):
            return "세션 폴더를 만들지 못했습니다 — \(error)"
        case .metadata(let underlying):
            return "세션 정보를 기록하지 못했습니다 — \(underlying)"
        }
    }
}

/// 세션 삭제 실패 (2-12).
///
/// **메타데이터 단계만 실패로 본다.** `ClipStore.delete` 와 같은 계약이다 —
/// 디렉터리 삭제가 실패해도 메타데이터가 이미 사라져 사용자가 본 결과는
/// 이미 "지워짐" 이고, 남는 것은 2-16 이 치울 고아 디렉터리뿐이다.
enum SessionDeleteError: Error, CustomStringConvertible {
    /// 메타데이터를 지우지 못했다. **세션도 클립도 디렉터리도 그대로 남아 있다.**
    case metadata(underlying: Error)

    var description: String {
        switch self {
        case .metadata(let underlying):
            return "세션을 지우지 못했습니다 — \(underlying)"
        }
    }
}

@MainActor
struct SessionStore {

    let context: ModelContext
    let files: SessionFileStore

    init(context: ModelContext, files: SessionFileStore = .shared) {
        self.context = context
        self.files = files
    }

    /// 세션을 시작한 결과. **새로 만든 것과 이어간 것을 구분한다.**
    ///
    /// 호출부가 둘을 구분해야 하는 이유는 화면 전환이 다르기 때문이다 —
    /// 새 세션은 촬영 화면으로 바로 들어가고(F-01 AC), 이어가기는 사용자에게
    /// 이어간다는 사실이 보여야 한다(3-9 진행 중 세션 배너).
    enum Start {
        case created(Session)
        case resumed(Session)

        var session: Session {
            switch self {
            case .created(let session), .resumed(let session): return session
            }
        }

        var isNew: Bool {
            if case .created = self { return true }
            return false
        }
    }

    // MARK: - 이어가기 (2-7)

    /// 이어서 촬영할 수 있는 세션. 없으면 `nil`.
    ///
    /// # 두 단계다
    ///
    /// ```
    /// inProgress() 로 fetch  →  Swift 에서 isResumable 필터
    /// ```
    ///
    /// **`isResumable` 을 `#Predicate` 에 넣을 수 없다.** `orientationState` 가
    /// `clips` 관계를 세는 계산 프로퍼티라 키패스가 없다. `#Predicate` 의 enum
    /// 미지원(CLAUDE.md)과는 별개의 제약이며, 그래서 조회는 저장 상태 기준으로
    /// 하고 판정은 코드에서 한다. `orientationRawIsNil()` 을 raw 기준으로
    /// 이름 붙인 것과 같은 규율이다.
    ///
    /// # 후보가 여럿이면 최신 하나
    ///
    /// **나머지는 건드리지 않는다.** 자동으로 닫으면 사용자 데이터를 우리
    /// 판단으로 마감하는 것이라 2-5 의 "어느 경우에도 녹화본을 지우지 않는다"
    /// 와 결이 맞지 않는다. 대신 로그를 남긴다 — 조용히 하나만 고르면 나머지가
    /// 있다는 사실을 알 수 없다.
    ///
    /// 정상 상태에서는 후보가 0개 또는 1개다. 여럿이면 그 자체가 이상 신호다.
    func resumableSession() throws -> Session? {
        let descriptor = FetchDescriptor<Session>(
            predicate: Session.inProgress(),
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])

        let open: [Session]
        do {
            open = try context.fetch(descriptor)
        } catch {
            throw SessionStartError.query(underlying: error)
        }

        let candidates = open.filter(\.isResumable)

        // 이어갈 수 없어서 걸러진 세션. 2-16 의 복구 대상이다.
        let excluded = open.count - candidates.count
        if excluded > 0 {
            print("[session] 이어가기 후보에서 제외 \(excluded)개 "
                  + "— 방향이 없거나 깨진 세션이다 (2-16 복구 대상)")
        }

        guard let newest = candidates.first else { return nil }

        // **`#if DEBUG` 로 감싼다 — 세션 id 와 사용자가 입력한 제목을 찍는다.**
        //
        // `StoreProbeLog` 를 파일 전체로 감싼 근거와 같다(Codex 리뷰 ③):
        // 파일 경로·세션 id 를 stdout 에 뿌리는 계측은 릴리스에 남기지
        // 않는다. `displayTitle` 은 사용자 입력이고, 세션 id 는 세션
        // 디렉터리 이름이라 파일 경로 단서가 된다.
        //
        // **바로 위 "제외 N개" 줄은 감싸지 않는다.** 개수만 찍고 세션을
        // 특정하지 않으므로 성격이 다르다.
        //
        // 3-13 에서 프로브·측정 코드를 정리할 때 이 줄도 함께 본다.
        // 한 줄짜리라 미루면 잊히므로 여기서 선반영했다.
        #if DEBUG
        if candidates.count > 1 {
            print("[session] ⚠ 이어갈 수 있는 세션이 \(candidates.count)개다. "
                  + "최신 하나만 이어간다 — \(newest.id.uuidString)")
            for other in candidates.dropFirst() {
                print("[session]   남겨둠 \(other.id.uuidString) "
                      + "\(other.displayTitle) · \(other.clips.count)컷")
            }
        }
        #endif

        return newest
    }

    // MARK: - 시작 (2-6 + 2-7)

    /// 진행 중 세션이 있으면 이어가고, 없으면 새로 만든다.
    ///
    /// **`startOrResume` 이 내부에서 직접 조회하는 것이 핵심이다.** F-01 AC
    /// ("진행 중 세션이 이미 있으면 새로 만들지 않는다")를 호출부의 분기에
    /// 맡기면, 배너를 그리지 않는 경로가 하나라도 생기는 순간 세션이 늘어나기
    /// 시작한다. 그런 증가는 조용해서 한참 뒤에 발견된다.
    ///
    /// 그래서 **세션을 무조건 만드는 API 는 밖에 두지 않는다.** `create` 는
    /// `private` 이며 이 함수만 부른다.
    ///
    /// # 이 함수는 동기여야 한다
    ///
    /// 조회(`resumableSession`)와 생성(`create`) 사이에 **suspension point 를
    /// 두지 않는다.** 지금은 전부 `@MainActor` 동기라 두 번 빠르게 눌러도
    /// 직렬화되고, 두 번째 호출은 이미 저장된 세션을 본다.
    ///
    /// **그 안전성은 `async` 가 없다는 사실 하나에 달려 있다.** 여기에 `await`
    /// 이 생기는 순간 확인과 행동 사이에 창이 열리고, 두 번 탭하면 세션이 둘
    /// 생기면서 F-01 AC 가 조용히 깨진다. 2-14 가 `createDirectory` 를 메인
    /// 밖으로 빼려 할 때가 가장 유력한 시점이다 — 그때는 이 계약을 먼저
    /// 다시 설계해야 한다.
    ///
    /// - Parameter title: 사용자가 입력한 제목. 비우면 `displayTitle` 이
    ///   날짜로 만든다. **이어가는 경우 이 값은 버린다** — 이름이 이미 있는
    ///   세션을 이어가는 것이다.
    @discardableResult
    func startOrResume(title: String = "") throws -> Start {
        if let existing = try resumableSession() {
            return .resumed(existing)
        }
        return .created(try create(title: title))
    }

    /// 세션 하나를 만든다 (2-6).
    ///
    /// # 순서: 디렉터리 먼저, 메타데이터 나중
    ///
    /// 세션 층에도 같은 불변식이 걸린다 — **메타데이터가 있으면 디렉터리도
    /// 있다.** 어긋나면 빈 디렉터리가 고아로 남고 2-16 이 치운다. 반대로
    /// 하면 클립을 쓸 자리가 없는 세션이 생겨 첫 촬영이 깨진다.
    ///
    /// 실기기에서 이 순서로 검증했다 (2-A). 프로브가 쓰던 순서를 그대로 옮겼다.
    ///
    /// # `save()` 를 명시적으로 부른다
    ///
    /// autosave 에 맡기면 저장 실패를 **관측조차 못 한다.** 프로브가 그랬다.
    /// `ClipStore` 와 같이 실패하면 `rollback()` 하고 분류해서 던진다.
    ///
    /// `rollback()` 은 이 컨텍스트의 **다른 미저장 변경도 함께 되돌린다.**
    /// 메인 컨텍스트를 공유하기 때문이며, 여기까지 온 이상 이미 실패 상태이므로
    /// 받아들인다. **인메모리 객체는 stale 로 남으므로**(CLAUDE.md "API
    /// 주의사항") 이 에러를 받은 쪽은 인메모리 세션을 믿지 말고 다시 읽어야 한다.
    ///
    /// # 방향은 여기서 정하지 않는다
    ///
    /// 생성 직후 세션 방향은 **미정**이다(F-01). 확정은 첫 클립 저장과 같은
    /// 저장 단위에서 일어나야 하며(2-8), 그 자리는 `ClipStore.save` 의
    /// `alsoApply` 다. 여기서 손대면 "클립이 없는데 방향이 있는" 세션이 생긴다.
    ///
    /// **그 상태는 저장 실패 경로로도 만들어질 수 있다.** `alsoApply` 가 정한
    /// 방향은 `update` 라 `rollback()` 이 인메모리를 되돌리지 않아서, 클립만
    /// 사라지고 방향이 남는다. `ClipStore.save` 의 `revertOnFailure` 가 그것을
    /// 걷어낸다 — 그쪽 실패 경로 주석에 같은 설명이 있다.
    private func create(title: String) throws -> Session {
        // 공백만 입력한 것은 입력하지 않은 것으로 본다. 저장 시점에 다듬어야
        // `title` 이 비었다는 사실이 "이름을 짓지 않았다" 와 정확히 같아진다.
        let session = Session(title: title.trimmingCharacters(in: .whitespacesAndNewlines))

        // 1) 디렉터리. 경로 조합·에러 분류가 전부 SessionFileStore 안에 있다.
        do {
            try files.createSessionDirectory(session.id)
        } catch let error as SessionFileError {
            throw SessionStartError.file(error)
        } catch {
            // `createSessionDirectory` 는 늘 `SessionFileError` 로 접어서
            // 던지므로 여기 오지 않는다. 그래도 열어두면 분류가 깨진다.
            throw SessionStartError.file(.failed(underlying: error))
        }

        // 2) 메타데이터.
        context.insert(session)
        do {
            try context.save()
        } catch {
            context.rollback()

            // **`rollback()` 만으로는 유령이 남는다** (2-7 리뷰에서 지적되어
            // 하네스로 실측). 저장 실패 후 측정한 결과가 갈렸다:
            //
            // - 새 컨테이너로 스토어를 다시 열면 **0개** — 스토어 기준으로는
            //   제대로 되돌아간다
            // - 그런데 **같은 컨텍스트에서 다시 조회하면 1개가 나온다.**
            //   `@Query` 가 이 유령을 화면에 그리고, 목록에 있으니 클립이
            //   그리로 들어갈 수도 있다
            //
            // CLAUDE.md 의 기존 실측("스토어 기준으로는 제대로 되돌린다")은
            // **업데이트** 사례였다. insert 는 다르다.
            //
            // **보유 참조로는 지워지지 않는다.** 여섯 조합을 재봤는데
            // `rollback()` 뒤에 우리가 들고 있는 `session` 을 `delete` 해도,
            // 순서를 바꿔도, `rollback` 없이 `delete` 만 해도 유령이 남았다.
            // **재조회해서 나온 인스턴스를 지워야** 사라진다 — 롤백 후의
            // 보유 참조는 컨텍스트에 등록된 것과 같은 객체가 아니다.
            //
            // 전체를 지우지 않는다. 방금 만든 id 하나만 걷어낸다.
            purgePhantom(id: session.id)

            // **디렉터리는 지우지 않는다.** 빈 디렉터리는 잃을 데이터가 없어
            // 고아로 두는 쪽이 안전하고, 2-16 이 치운다. 여기서 지우려다
            // 실패하면 오히려 처리할 것이 하나 더 생긴다.
            throw SessionStartError.metadata(underlying: error)
        }

        return session
    }

    // MARK: - 삭제 (2-12)

    /// 세션 하나를 지운 결과.
    struct Deletion {
        /// 디렉터리가 실제로 있었고 지워졌으면 `true`.
        /// 이미 없었으면 `false` — **실패가 아니다.**
        let directoryRemoved: Bool
    }

    /// 세션을 지운다. 메타데이터(세션 + 클립)와 디렉터리를 함께 없앤다.
    ///
    /// # 순서: 메타데이터 먼저, 디렉터리 나중
    ///
    /// CLAUDE.md "메타데이터와 파일의 정합성" 이 세션 층에도 그대로 걸린다 —
    /// **메타데이터가 있으면 파일도 있다.** 어긋나면 고아 디렉터리 쪽으로
    /// 떨어지고 2-16 이 조용히 치운다.
    ///
    /// **뒤집으면 안 되는 이유를 실측으로 굳혔다** (2-12 조사, 반증 실험).
    /// 디렉터리를 먼저 지우고 `save()` 를 실패시켰더니 재실행 시점에
    /// **세션 1개 · 클립 2개 · 디렉터리 없음** 이 남았다. 화면에는 컷이 있는데
    /// 재생도 병합도 안 되는 세션이며, **스토어에 영구히 남는다.**
    /// 메타 먼저면 저장이 실패해도 디렉터리를 아직 안 건드렸으므로 그 상태가
    /// 만들어지지 않는다.
    ///
    /// # 클립을 하나씩 지우지 않는다
    ///
    /// `Session.clips` 의 `deleteRule: .cascade` 가 클립 메타데이터를 함께
    /// 지운다. **선언을 믿지 않고 실측했다** (2-12 조사) — 이 프로젝트는
    /// SwiftData 선언 동작이 예상과 다른 것을 세 번 밟았다(`#Predicate` enum
    /// 미지원 · `transaction` 이 롤백하지 않음 · `rollback()` 이 insert 를
    /// 인메모리에 남김).
    ///
    /// 새 컨테이너 재조회에서 `Clip` 0개, 같은 컨텍스트에도 유령 0개였고,
    /// **`clips` 관계를 한 번도 읽지 않고 지워도 돌았다.** 목록에서 세션을
    /// 골라 지우는 실사용이 그 모양이라 따로 확인했다.
    ///
    /// 파일은 cascade 가 지우지 않는다 — 그것이 아래 2)가 있는 이유다.
    ///
    /// # 디렉터리 삭제 실패는 실패가 아니다
    ///
    /// 2-5 와 같은 계약이다. 메타데이터가 이미 사라져 **사용자가 본 결과는
    /// 이미 "지워짐"** 이고, 되돌리려고 메타데이터를 되살리면 지운 세션이
    /// 목록에 다시 나타나 더 놀란다.
    ///
    /// **손실 규모는 2-5 보다 크다** — 클립 하나가 아니라 세션 전체(30컷이면
    /// 570MB)가 고아로 남는다. 그래도 결론은 같다. 사용자가 명시적으로
    /// "지운다" 를 눌렀고, 이 실패로 눈에 보이는 결과를 뒤집는 것이 더 나쁘다.
    ///
    /// # 사진 앱의 완성본은 건드리지 않는다
    ///
    /// 우리 소유가 아니다. 2-12a 로 닫힌 세션이라도 사용자가 이미 자기
    /// 라이브러리에 가진 것이고, 지우는 것은 **앱 내부 데이터뿐**이다.
    @discardableResult
    func delete(_ session: Session) throws -> Deletion {
        // id 를 지금 챙긴다. 삭제 후에 `session` 을 읽지 않는다.
        let id = session.id

        // 1) 메타데이터. `.cascade` 가 클립을 함께 데려간다.
        context.delete(session)
        do {
            try context.save()
        } catch {
            // 통째로 되돌린다. 세션도 클립도 살아 있고 디렉터리는 애초에
            // 손대지 않았다.
            //
            // **인메모리를 되돌리지 않는다. 되돌릴 대상이 없기 때문이다.**
            // 2-10 이 `ClipStore.delete` 의 `catch` 에서 방향과 `order` 를
            // 명시적으로 복원한 것과 다른데, 그쪽은 **`fetch` 를 아무리 돌려도
            // 스스로 고쳐지지 않는** stale 이었다. 여기는 다르다 —
            // **2회차 조회부터 저절로 맞는다**(바로 아래).
            //
            // 탈락한 두 안:
            //
            // - `context.insert(session)` 으로 되살리기 — 이미 스토어에 있는
            //   객체를 `insert` 하는 것이 계약상 맞는지 불확실하다
            // - `catch` 에서 더미 `fetch<Session>` 을 한 번 더 돌려 2회차를
            //   앞당기기 — `fetch` 는 대상을 지정하는 API 가 아니라 **전체를
            //   다시 읽는** API 다. 되돌릴 대상이 세션 하나여도 흔드는 범위는
            //   같고, 2-10 에서 같은 이유로 탈락시켰다(`purgePhantom` 이 "방금
            //   만든 id 하나만" 걷어내는 것과 대비된다)
            //
            // ⚠ **알려진 동작: 같은 컨텍스트의 첫 `fetch` 가 거짓말한다.**
            // 나중에 발견될 버그가 아니라 지금 아는 동작이다.
            //
            //     rollback 후 fetch<Session> 1회차 → 0개
            //     rollback 후 fetch<Session> 2회차 → 1개   (3회 반복 실측)
            //
            // 스토어는 온전하고 `session.isDeleted` 도 `false` 이며 클립은
            // 그 사이에도 살아 있다. **실사용에서는 이렇게 나타난다** — 삭제
            // 실패 에러를 던진 직후 `@Query` 가 다시 도는데 그 조회가 1회차라
            // **세션이 목록에서 사라진다.** 사용자는 "삭제 실패 에러를 보면서
            // 동시에 목록에서 사라진 화면" 을 보고, 앱을 다시 켜면 부활한다.
            // 3-8(세션 목록)·3-15(에러 표시)가 이 사실을 알아야 한다.
            context.rollback()
            throw SessionDeleteError.metadata(underlying: error)
        }

        // 2) 디렉터리. 여기서 실패해도 **되돌리지 않는다.**
        var directoryRemoved = false
        do {
            directoryRemoved = try files.removeSessionDirectory(id)
        } catch {
            // 삼키지 않고 흔적을 남긴다. 실패해도 호출부에는 성공이다.
            print("[session] ✕ 디렉터리 삭제 실패 \(id.uuidString) — \(error)."
                  + " 고아로 남으며 2-16 이 치운다")
        }

        return Deletion(directoryRemoved: directoryRemoved)
    }

    /// 저장에 실패해 롤백된 세션이 컨텍스트에 남아 있으면 걷어낸다.
    ///
    /// **스토어에는 없다** — 새 컨테이너로 열어보면 0개다. 남는 것은 이
    /// 컨텍스트의 등록뿐인데, `@Query` 가 그것을 읽어 화면에 유령 세션을
    /// 그리고 그 목록을 보고 클립이 그리로 들어갈 수도 있다.
    ///
    /// 실패해도 삼킨다. 여기까지 온 것은 이미 저장 실패 경로이고, 정리에
    /// 실패해도 던질 새 정보가 없다 — 호출부가 받아야 할 것은 원래의
    /// `.metadata` 에러다.
    private func purgePhantom(id: UUID) {
        guard let phantom = try? context.fetch(FetchDescriptor<Session>())
            .first(where: { $0.id == id }) else { return }
        context.delete(phantom)
    }
}
