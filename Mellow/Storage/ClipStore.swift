import Foundation
import SwiftData

// 클립 저장 (2-4). **파일 이동과 메타데이터 기록을 하나의 단위로 다룬다.**
//
// 완전한 원자성은 불가능하다 — 파일시스템과 SwiftData 는 다른 저장소다.
// 그래서 **어긋났을 때 덜 나쁜 방향으로 기울인다.** 순서 판단은
// `save(clipAt:...)` 주석 참고.

/// 클립 저장 실패. 파일 단계와 메타데이터 단계를 구분한다 —
/// 남는 쓰레기의 종류가 다르다.
enum ClipSaveError: Error, CustomStringConvertible {
    /// 파일을 옮기지 못했다. **메타데이터는 만들어지지 않았고 원본은 그대로다.**
    /// `.file(.outOfSpace)` 를 2-14 가 구분해서 쓴다.
    case file(SessionFileError)
    /// 파일은 옮겼는데 메타데이터를 쓰지 못했다.
    ///
    /// **원본이 제자리로 돌아가 있으므로 같은 URL 로 재시도할 수 있다.**
    /// 이것이 이 에러의 계약이다 — 녹화본을 지우지 않는다.
    ///
    /// 되돌리기까지 실패한 경우에만 예외적으로 파일이 세션 디렉터리에
    /// 고아로 남는다. 그때는 재시도가 안 되지만 파일이 사라지지도 않는다.
    /// 어느 쪽이든 **메타데이터는 남지 않는다.**
    ///
    /// 재시도를 실제로 줍는 경로는 아직 없다. 2-14가 즉시 재시도의 의미를
    /// 판단하고 3-15가 사용자 주도 재시도를 붙인다.
    case metadata(underlying: Error)

    var description: String {
        switch self {
        case .file(let error):
            return "클립 파일을 옮기지 못했습니다 — \(error)"
        case .metadata(let underlying):
            return "클립 정보를 기록하지 못했습니다 — \(underlying)"
        }
    }
}

/// 클립 삭제 실패.
///
/// **메타데이터 단계만 실패로 본다.** 파일 삭제가 실패해도 사용자가 본
/// 결과는 이미 "지워짐"이고 남는 것은 2-16 이 치울 고아 파일뿐이다.
enum ClipDeleteError: Error, CustomStringConvertible {
    /// 메타데이터를 지우지 못했다. **클립도 파일도 그대로 남아 있다.**
    case metadata(underlying: Error)

    var description: String {
        switch self {
        case .metadata(let underlying):
            return "클립을 지우지 못했습니다 — \(underlying)"
        }
    }
}

/// 메인 컨텍스트 전용이다 (CLAUDE.md "SwiftData 사용 원칙").
@MainActor
struct ClipStore {

    let context: ModelContext
    let files: SessionFileStore

    init(context: ModelContext, files: SessionFileStore = .shared) {
        self.context = context
        self.files = files
    }

    /// 녹화가 끝난 파일을 세션 디렉터리로 옮기고 `Clip` 을 기록한다.
    ///
    /// # 순서: 파일 먼저, 메타데이터 나중
    ///
    /// 어긋나는 방향이 둘인데 **나쁜 정도가 다르다.**
    ///
    /// - 파일을 옮긴 뒤 메타데이터 전에 죽으면 → **고아 파일.** 사용자는
    ///   클립이 저장됐다고 들은 적이 없고, 재생·병합에 끼어들지도 않는다.
    ///   2-16 이 조용히 지우면 끝난다
    /// - 메타데이터를 먼저 쓰고 파일 이동이 실패하면 → **파일 없는 클립.**
    ///   화면에는 클립이 늘어나 있는데 실체가 없다. 사용자에게 거짓을 보이고,
    ///   그 세션의 병합·미리보기가 2-16 이 돌 때까지 깨진다
    ///
    /// 뒤쪽이 명백히 나쁘므로 **파일을 먼저 옮긴다.** 메타데이터가 실패하면
    /// 옮긴 파일을 **원래 자리로 되돌려** 같은 URL 로 재시도할 수 있게 하고,
    /// 그 되돌리기마저 실패하면 남는 것은 고아 파일 — 여전히 덜 나쁜 쪽이다.
    /// **어느 경우에도 녹화본을 지우지 않는다.**
    ///
    /// # 이동이지 복사가 아니다
    ///
    /// 원본은 `temporaryDirectory`, 목적지는 세션 디렉터리이며 **둘 다 앱
    /// 컨테이너 안이라 같은 볼륨**이다. 같은 볼륨의 이동은 rename 이라
    /// 사실상 공짜고 디스크를 두 배로 쓰지 않는다. 10초 클립이 약 19MB 라
    /// 복사하면 저장 공간이 빠듯할 때(2-14) 불리하다.
    ///
    /// 1-19 에서 사진 앱 저장에 복사를 고른 것은 **다른 맥락이다.** 그쪽은
    /// 외부 프로세스로 넘기는 것이라 실패 시 재시도할 원본이 필요했다.
    /// 여기서는 `moveItem` 이 실패해도 원본이 제자리에 남으므로 재시도
    /// 여지가 그대로다.
    ///
    /// # 첫 클립의 세션 방향 (2-8)
    ///
    /// `alsoApply` 로 넘긴 변경은 **클립 기록과 같은 저장 단위 안에서**
    /// 적용된다. 2-8 이 여기에 방향 확정을 넣는다. 나눠서 `save()` 하면
    /// "클립이 있는데 `orientation` 이 nil" 인 세션이 생긴다.
    ///
    /// **`revertOnFailure` 는 그 짝이다.** 저장이 실패하면 이 함수는 파일을
    /// 원래 자리로 되돌리고 유령 클립을 걷어낸다 — 원상복구를 저장 단위
    /// **안에서** 한다. 세션 변경만 밖에 두면 그 대칭이 깨지고, 깨진 것을
    /// 한참 뒤에 발견하는 일이 2-7→2-8 에서 실제로 일어났다.
    ///
    /// `alsoApply` 안에서 **파일을 읽지 마라.** 이 함수는 동기이고 메인
    /// 액터다. 판정은 호출부(async)에서 끝내고 값만 넘긴다.
    ///
    /// - Parameters:
    ///   - duration: **파일에서 읽은 실제 길이(초).** 버튼을 누른 시간이
    ///     아니다 — 녹화 시작 지연이 0.077~0.174초로 일정하지 않아 누른
    ///     시간으로는 판정이 되지 않는다 (1-7).
    ///   - alsoApply: 같은 저장 단위에 넣을 세션 변경. **이 클립이 관계에
    ///     붙기 전에 불린다** — 클로저가 보는 `session.clips` 에는 지금 넣는
    ///     클립이 없다. "첫 클립인가"를 판단할 수 있게 하려는 것이며, 이유는
    ///     아래 구현 주석 참고.
    ///   - revertOnFailure: 저장이 실패했을 때 그 세션 변경을 **인메모리에서**
    ///     되돌리는 짝. `alsoApply` 를 넘기지 않았으면 불리지 않는다.
    ///     **무엇을 되돌릴지는 호출부가 안다** — `alsoApply` 가 실제로 값을
    ///     바꿨는지까지 호출부가 판단해서 넘긴다.
    @discardableResult
    func save(clipAt sourceURL: URL,
              duration: Double,
              to session: Session,
              recordedAt: Date = Date(),
              alsoApply sessionChanges: ((Session) -> Void)? = nil,
              revertOnFailure sessionRevert: ((Session) -> Void)? = nil) throws -> Clip {

        let sessionID = session.id
        let clipID = UUID()

        // 파일명은 클립 id 에서 나온다. `order` 로 짓지 않는다 — 2-5 가
        // 삭제 후 order 를 재정렬하는데, 그때마다 파일을 개명할 수는 없다.
        let fileName = "\(clipID.uuidString).mov"

        // 1) 파일. 이동·디렉터리 보장·에러 분류가 전부 SessionFileStore 안에
        //    있다. 이 층은 FileManager 를 직접 부르지 않는다.
        do {
            try files.adopt(fileAt: sourceURL, as: fileName, in: sessionID)
        } catch let error as SessionFileError {
            throw ClipSaveError.file(error)
        } catch {
            // `adopt` 는 늘 `SessionFileError` 로 접어서 던지므로 여기 오지
            // 않는다. 그래도 열어두면 `ClipSaveError` 가 아닌 것이 새어나가
            // 호출부의 분류가 깨지므로 막아둔다.
            throw ClipSaveError.file(.failed(underlying: error))
        }

        // 2) 메타데이터.
        //
        // 클립 삽입과 세션 변경을 다 해놓고 **`save()` 를 한 번만** 부른다.
        // 이 함수는 전부 동기이고 메인 액터에서 돌므로 그 사이에 autosave 가
        // 끼어들 수 없다 — 중간에 반쯤 저장되는 상태가 생기지 않는다.
        //
        // `transaction(block:)` 은 쓰지 않는다. 블록이 던져도 인메모리 변경을
        // 되돌리지 않아 이름값을 못 한다 (실측. CLAUDE.md "API 주의사항" 참고).

        // **세션 변경이 클립 부착보다 먼저다.** 순서에 이유가 있다.
        //
        // `Clip(session:)` 은 그 자리에서 관계를 맺으므로, insert 뒤에는
        // `session.clips` 에 새 클립이 이미 들어가 있다. 그런데
        // `orientationState` 가 그 관계를 세기 때문에 **방향이 아직 없는
        // 세션이 그 순간 `.unset` 이 아니라 `.missing` 으로 보인다** — 저장
        // 단위 안에서만 스쳐 지나가는, 실제로는 존재하지 않는 상태다.
        //
        // 그 상태에서 `Session.decideOrientation` 을 부르면 가드가 `.unset` 을
        // 요구하므로 **첫 클립이 방향을 영영 정하지 못한다.** 2-8 구현 첫
        // 시도가 정확히 여기서 걸렸고 하네스 9군이 잡았다.
        //
        // 가드를 `.missing` 까지 허용하도록 푸는 것은 답이 아니다. 그러면
        // **2-8 이전에 만들어진 진짜 손상 세션의 방향을 다음 촬영이 새로
        // 정하게 되고**, 계열이 다르면 한 세션에 세로·가로가 섞인다.
        //
        // 그래서 클로저에게 **이 클립이 붙기 전의 세션**을 보여준다. "첫 클립이
        // 방향을 정한다"는 말의 판단 기준이 원래 그것이다 — 지금 넣으려는
        // 클립을 뺀 나머지가 비어 있는가. 둘 다 `save()` 앞이므로 **저장 단위는
        // 그대로 하나**이고, 어느 쪽이 먼저든 스토어에는 함께 들어간다.
        sessionChanges?(session)

        let clip = Clip(id: clipID,
                        order: nextOrder(in: session),
                        fileName: fileName,
                        duration: duration,
                        recordedAt: recordedAt,
                        session: session)
        context.insert(clip)

        do {
            try context.save()
        } catch {
            // **스토어 기준으로만** 이 단위를 통째로 되돌린다. 클립 삽입과
            // `sessionChanges` 가 스토어에서 함께 사라진다.
            //
            // **인메모리는 되돌아가지 않는다.** 이것이 이 아래 세 덩어리가
            // 존재하는 이유다 (CLAUDE.md "API 주의사항"). 남는 것이 둘인데
            // 성질이 달라 푸는 방법도 다르다.
            //
            // - **클립은 `insert`** → 롤백 후 유령으로 남는다. 재조회해서
            //   나온 인스턴스와 우리가 들고 있는 참조 **두 군데**를 따로
            //   풀어야 한다 (바로 아래)
            // - **세션 변경은 `update`** → 롤백해도 우리가 들고 있는 객체는
            //   **바뀐 값을 그대로 들고 있다(stale).** 걷어내는 코드가 여기
            //   없으면 아무도 되돌리지 않는다 → `revertOnFailure`
            //
            // **`context.delete(clip)` 으로는 부족하다** — 클립만 빠지고
            // 세션 변경은 다음 저장 때 그대로 들어간다 (실측).
            //
            // 이 컨텍스트의 **다른 미저장 변경도 함께 사라진다.** 메인
            // 컨텍스트를 공유하기 때문이며, 여기까지 온 이상 이미 실패
            // 상태이므로 받아들인다. 그래서 이 에러를 받은 쪽은 인메모리
            // 세션을 믿지 말고 다시 읽는 것이 여전히 옳다 — 아래 정리는
            // **우리가 건드린 것**을 되돌릴 뿐이고 그 이상을 보장하지 않는다.
            context.rollback()

            // 세션 변경을 인메모리에서 되돌린다.
            //
            // **스토어에는 애초에 들어가지 않았으므로 2-16 이 이 어긋남을
            // 영영 검출하지 못한다.** 인메모리에만 있는 상태라 규율로 지킬
            // 수 없고, 그래서 코드로 막는다.
            //
            // 방향으로 예를 들면(2-8): 되돌리지 않으면 스토어는 "방향 없음 ·
            // 클립 없음" 인데 인메모리는 "방향 있음 · 클립 없음" 이 된다.
            // `orientationState` 가 `.decided` 라 다음 촬영이 방향을 이미
            // 정해진 것으로 읽고, 2-9 가 들어오면 **클립이 하나도 없는
            // 세션에서 녹화가 막힌다.** `SessionStore.create` 가 "여기서
            // 손대면 클립이 없는데 방향이 있는 세션이 생긴다" 고 경고한
            // 그 상태가 실패 경로로 만들어지는 것이다.
            //
            // `alsoApply` 를 받지 않았으면 되돌릴 것도 없다.
            if sessionChanges != nil {
                sessionRevert?(session)
            }

            // **`rollback()` 만으로는 유령 클립이 남는다** (2-7 에서 같은 것을
            // 발견해 여기도 재봤다). `allowsSave: false` 하네스 실측:
            //
            // - 새 컨테이너로 스토어 재조회 → **0개.** 스토어는 깨끗하다
            // - 같은 컨텍스트 재조회 → **1개**
            // - `session.clips` / `orderedClips` → **1개.** 병합 대상에 들어간다
            // - `orientationState` 가 `.unset` → **`.missing` 으로 바뀐다**
            //
            // 마지막 둘이 `SessionStore` 보다 나쁘다. 파일은 `release` 로
            // 되돌아갔는데 화면에는 클립이 남아 있으니 **2-4 가 피하려던
            // "파일 없는 메타데이터" 가 인메모리에 정확히 만들어진다.** 게다가
            // `.missing` 이 되면 2-7 이 그 세션을 이어가기 후보에서 빼버린다.
            //
            // **두 군데를 따로 풀어야 한다.** 관계는 우리가 들고 있는 참조가
            // 쥐고 있고, 컨텍스트 등록은 재조회해서 나오는 인스턴스가 쥐고 있다.
            // 둘은 같은 객체가 아니라서 한쪽만 손보면 다른 쪽이 남는다 (실측).
            //
            //   보유 `clip.session = nil` 만  → 컨텍스트에 남는다
            //   재조회 `delete` 만            → 관계에 남는다
            //   재조회 인스턴스의 `session = nil` → 관계에 남는다 (보유 참조가 아니다)
            clip.session = nil
            purgePhantom(id: clipID)

            // 옮긴 파일을 **원래 자리로 되돌린다. 지우지 않는다.**
            //
            // 지우면 방금 찍은 녹화본의 유일한 사본이 사라지고, 같은
            // `sourceURL` 로 재시도할 수도 없다. `save()` 가 실패하는 현실적
            // 원인은 저장 공간 부족인데 그때가 하필 사용자가 방금 찍은 것을
            // 잃으면 안 되는 상황이다 (2-5 Codex 리뷰 P1).
            //
            // 되돌린 자리가 `temporaryDirectory` 라 영원하지는 않다. 그래도
            // 즉시 삭제와는 다르다 — 재시도 창이 0이냐 0보다 크냐의 차이다.
            do {
                try files.release(fileName: fileName, in: sessionID, to: sourceURL)
            } catch {
                // 되돌리기까지 실패하면 파일은 세션 디렉터리에 고아로 남는다.
                // 재시도는 못 하지만 지우는 것보다는 낫다 — 2-16 이 치운다.
                print("[clip] ✕ 되돌리기 실패 \(fileName) — \(error). 고아로 남으며 2-16 이 치운다")
            }
            throw ClipSaveError.metadata(underlying: error)
        }

        return clip
    }

    /// 다음 `order`.
    ///
    /// **최대값 + 1이다. 개수가 아니다.** 2-5 가 삭제 후 재정렬하므로 보통
    /// 둘이 같지만, 재정렬이 어떤 이유로든 끝나지 않았을 때 개수를 쓰면
    /// **이미 있는 order 와 겹친다.** 겹치면 정렬이 모호해져 완성본의 컷
    /// 순서가 흔들린다. 빈 번호가 생기는 것은 정렬에 아무 영향이 없다 —
    /// **틈은 무해하고 중복은 해롭다.**
    ///
    /// 2-16 이 파일 없는 메타데이터를 지우면 재정렬 없이 틈이 생길 수 있다.
    /// 그 경로가 있는 한 이 선택은 계속 유효하다.
    private func nextOrder(in session: Session) -> Int {
        (session.clips.map(\.order).max() ?? -1) + 1
    }

    /// 저장에 실패해 롤백된 클립이 컨텍스트에 남아 있으면 걷어낸다.
    ///
    /// `SessionStore.purgePhantom(id:)` 와 같은 모양이다. **합치지 않았다** —
    /// 제네릭으로 뽑으려면 `id: UUID` 를 요구하는 프로토콜을 새로 만들고 두
    /// 모델에 채택시켜야 하는데, 그 표면이 이 8줄짜리 `private` 함수 둘보다
    /// 크다. 그리고 세 번째 소비자가 생길 것 같지 않다 — **`insert` 하는 곳만
    /// 해당하고**, 2-12a(`isClosed` 갱신)와 2-18(`duration` 갱신)은 둘 다
    /// 업데이트라 이 문제에 걸리지 않는다. 세 번째가 실제로 오면 그때 뽑는다.
    private func purgePhantom(id: UUID) {
        guard let phantom = try? context.fetch(FetchDescriptor<Clip>())
            .first(where: { $0.id == id }) else { return }
        context.delete(phantom)
    }

    // MARK: - 삭제 (2-5)

    /// 클립 하나를 지운 결과.
    struct Deletion {
        /// 이 세션에 남은 클립 수.
        let remainingCount: Int
        /// 파일이 실제로 있었고 지워졌으면 `true`.
        /// 이미 없었으면 `false` — 실패가 아니다.
        let fileRemoved: Bool

        /// **이 삭제로 클립이 0개가 되었는가.**
        /// 2-10(클립 0개면 방향 미정으로 초기화)이 이 값을 본다.
        var sessionBecameEmpty: Bool { remainingCount == 0 }
    }

    /// 클립을 지운다. 파일과 메타데이터를 함께 없애고 `order` 를 다시 매긴다.
    ///
    /// # 순서: 메타데이터 먼저, 파일 나중 — **2-4와 반대다**
    ///
    /// 순서가 뒤집힌 것이지 원칙이 뒤집힌 것이 아니다. 지키는 것은 늘 하나다:
    /// **메타데이터가 있으면 파일도 있다.**
    ///
    /// - 저장에서는 파일을 먼저 놓아야 메타데이터가 파일보다 앞서지 않는다
    /// - 삭제에서는 메타데이터를 먼저 지워야 메타데이터가 파일보다 오래 남지 않는다
    ///
    /// 파일을 먼저 지우면 그 사이에 죽었을 때 **파일 없는 클립**이 남는다.
    /// 화면에는 컷이 있는데 재생도 병합도 안 되는 상태이고, 2-16 이 돌기
    /// 전까지 그 세션이 깨진다. 반대로 메타데이터를 먼저 지우면 남는 것은
    /// **고아 파일**뿐이라 2-16 이 조용히 치우면 끝난다.
    ///
    /// # 재정렬은 삭제와 같은 저장 단위다
    ///
    /// 삭제와 재번호를 다 해놓고 `save()` 를 한 번 부른다. 그래서
    /// **재정렬이 절반만 반영되는 상태는 스토어에 생기지 않는다** — 저장이
    /// 실패하면 통째로 되돌아가고 클립은 그대로 남는다.
    ///
    /// 남은 클립 전부에 0부터 다시 매긴다. 뒤쪽만 당기지 않는 이유는 이미
    /// 있던 틈(2-16 이 만든)도 같이 메워지기 때문이다. 값이 그대로인 클립은
    /// 건드리지 않는다.
    ///
    /// `fileName` 은 클립 id 에서 나오므로 **재정렬해도 파일을 개명하지
    /// 않는다** (2-4 결정).
    ///
    /// # 마지막 클립도 같은 경로다
    ///
    /// 재정렬할 뒤쪽이 없을 뿐이고 분기하지 않는다. 2-11(마지막 컷 undo)이
    /// 이 함수를 그대로 쓴다.
    @discardableResult
    func delete(_ clip: Clip) throws -> Deletion {
        let session = clip.session
        let fileName = clip.fileName

        // 남길 클립을 지금 정한다. 삭제 후의 `session.clips` 를 믿지 않는다 —
        // 관계가 언제 갱신되는지에 기대지 않기 위해서다.
        let remaining = (session?.clips ?? [])
            .filter { $0.id != clip.id }
            .sorted { $0.order < $1.order }

        // 1) 메타데이터. 삭제와 재번호가 한 단위다.
        context.delete(clip)
        for (index, each) in remaining.enumerated() where each.order != index {
            each.order = index
        }

        do {
            try context.save()
        } catch {
            // 통째로 되돌린다. 클립은 살아 있고 파일도 그대로다.
            // 인메모리 객체는 stale 이므로 이 에러를 받은 쪽은 다시 읽어야 한다
            // (CLAUDE.md "API 주의사항").
            context.rollback()
            throw ClipDeleteError.metadata(underlying: error)
        }

        // 2) 파일. 여기서 실패해도 **되돌리지 않는다.**
        //
        // 메타데이터가 이미 사라져 사용자가 본 결과는 이미 "지워짐"이다.
        // 남는 것은 고아 파일이고 2-16 이 치운다. 되돌리려고 메타데이터를
        // 되살리면 오히려 지운 컷이 되살아나 사용자를 놀라게 한다.
        var fileRemoved = false
        if let sessionID = session?.id {
            do {
                fileRemoved = try files.removeClip(fileName: fileName, in: sessionID)
            } catch {
                // 삼키지 않고 흔적을 남긴다. 실패해도 호출부에는 성공이다.
                print("[clip] ✕ 파일 삭제 실패 \(fileName) — \(error). 고아로 남으며 2-16 이 치운다")
            }
        }

        return Deletion(remainingCount: remaining.count, fileRemoved: fileRemoved)
    }
}
