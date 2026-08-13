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
    /// 파일은 옮겼는데 메타데이터를 쓰지 못했다. **옮긴 파일은 되돌렸다.**
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
    /// 옮긴 파일을 되돌려 고아조차 남기지 않고, 그 되돌리기마저 실패하면
    /// 남는 것은 고아 파일 — 여전히 덜 나쁜 쪽이다.
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
    /// # 첫 클립의 세션 방향 (2-8 이 쓸 자리)
    ///
    /// `alsoApply` 로 넘긴 변경은 **클립 기록과 같은 저장 단위 안에서**
    /// 적용된다. 2-8 은 여기에 방향 확정을 넣으면 된다. 나눠서 `save()`
    /// 하면 "클립이 있는데 `orientation` 이 nil" 인 세션이 생긴다.
    ///
    /// - Parameters:
    ///   - duration: **파일에서 읽은 실제 길이(초).** 버튼을 누른 시간이
    ///     아니다 — 녹화 시작 지연이 0.077~0.174초로 일정하지 않아 누른
    ///     시간으로는 판정이 되지 않는다 (1-7).
    ///   - alsoApply: 같은 저장 단위에 넣을 세션 변경.
    @discardableResult
    func save(clipAt sourceURL: URL,
              duration: Double,
              to session: Session,
              recordedAt: Date = Date(),
              alsoApply sessionChanges: ((Session) -> Void)? = nil) throws -> Clip {

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
        let clip = Clip(id: clipID,
                        order: nextOrder(in: session),
                        fileName: fileName,
                        duration: duration,
                        recordedAt: recordedAt,
                        session: session)
        context.insert(clip)
        sessionChanges?(session)

        do {
            try context.save()
        } catch {
            // 스토어 기준으로 이 단위를 통째로 되돌린다. 클립 삽입과
            // `sessionChanges` 가 함께 사라진다.
            //
            // **`context.delete(clip)` 으로는 부족하다** — 클립만 빠지고
            // 세션 변경은 다음 저장 때 그대로 들어간다 (실측).
            //
            // 주의 두 가지:
            // - 이 컨텍스트의 **다른 미저장 변경도 함께 사라진다.** 메인
            //   컨텍스트를 공유하기 때문이며, 여기까지 온 이상 이미 실패
            //   상태이므로 받아들인다
            // - **인메모리 객체는 stale 로 남는다.** 스토어는 맞지만 우리가
            //   들고 있는 `session.clips` 에는 없어진 클립이 남아 있다.
            //   이 에러를 받은 쪽은 인메모리 세션을 믿지 말고 다시 읽어야 한다
            context.rollback()

            // 옮긴 파일도 되돌린다. 이것마저 실패하면 고아 파일이 남고,
            // 그건 2-16 이 치운다 — 여전히 덜 나쁜 쪽이다.
            try? files.removeClip(fileName: fileName, in: sessionID)
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
