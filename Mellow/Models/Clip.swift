import Foundation
import SwiftData

/// 10초 컷 하나의 메타데이터. 영상 파일 자체는 파일시스템에 있다.
///
/// **상태 필드가 없다.** 정규화 여부는 세션 방향과 파일의 `preferredTransform`
/// 으로 언제든 다시 계산되는 파생값이고, 진실은 파일이다 (2-17).
/// 따라서 이 타입에는 enum 프로퍼티가 없고 `#Predicate` 의 enum 제약에도
/// 걸리지 않는다.
@Model
final class Clip {
    var id: UUID

    /// 세션 안에서의 순서. 클립 삭제 시 재정렬된다 (2-5).
    var order: Int

    /// **세션 디렉터리 기준 상대 경로다.** 절대 경로는 저장하지 않는다 —
    /// iOS 는 앱 재설치·복원 시 컨테이너 경로가 바뀐다 (PRD 7장).
    /// 경로 조합은 파일 관리자가 맡는다 (2-3).
    var fileName: String

    /// 초 단위. **정규화 후 갱신된다 (2-18)** — 재인코딩이 CFR 정규화를 하면서
    /// 원본 길이와 무관하게 5980/600(9.966667s)으로 수렴한다. 갱신하지 않으면
    /// 세션 총 길이 표시와 병합 커서 전진이 실제와 어긋난다.
    var duration: Double

    var recordedAt: Date

    /// 역관계. 삭제 규칙은 `Session.clips` 쪽에 있다.
    var session: Session?

    init(
        id: UUID = UUID(),
        order: Int,
        fileName: String,
        duration: Double,
        recordedAt: Date = Date(),
        session: Session? = nil
    ) {
        self.id = id
        self.order = order
        self.fileName = fileName
        self.duration = duration
        self.recordedAt = recordedAt
        self.session = session
    }
}
