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

        if candidates.count > 1 {
            print("[session] ⚠ 이어갈 수 있는 세션이 \(candidates.count)개다. "
                  + "최신 하나만 이어간다 — \(newest.id.uuidString)")
            for other in candidates.dropFirst() {
                print("[session]   남겨둠 \(other.id.uuidString) "
                      + "\(other.displayTitle) · \(other.clips.count)컷")
            }
        }

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
