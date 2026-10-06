import Foundation

// Shared, pure presentation state for a Phase 6 import operation: the Blocking Preparation Sheet's progress
// (ADR-050 050-D D7b §5, ADR-042 Revision 4 §1), the consolidated exclusion notice copy (ADR-042 Revision 3 / 4 §6,
// ADR-043 Revision 1, ADR-044 Revision 1) and the Retry prompts (ADR-042 Revision 4 §3, 050-C CR, D7b §1). No
// timers, no fabricated values; only the copy the accepted decisions name.

/// Progress of ONE attempt. Only normalization-required items count, with equal weights:
/// `aggregate = (completed normalization items + current item's progress) / normalization item count`.
/// Item progress is clamped to `0...1` and never decreases within an item; events for unknown or already finished
/// items are ignored. A new attempt starts from a new value (progress resets per attempt).
struct ImportPreparationProgress: Equatable, Sendable {
    /// The normalization items in Accepted Set order.
    let normalizationIDs: [ImportCandidateID]
    private(set) var completed: Set<ImportCandidateID> = []
    private(set) var currentID: ImportCandidateID?
    private(set) var currentFraction: Double = 0

    init(normalizationIDs: [ImportCandidateID]) {
        self.normalizationIDs = normalizationIDs
    }

    var total: Int { normalizationIDs.count }

    /// 1-based ordinal of the item being normalized (the first item before any starts; the last once all finished).
    var position: Int {
        guard total > 0 else { return 0 }
        if let currentID, let index = normalizationIDs.firstIndex(of: currentID) { return index + 1 }
        return min(completed.count + 1, total)
    }

    /// ADR-042 R4 §1: the `2/5` position is shown only when there is more than one normalization item.
    var positionLabel: String? { total > 1 ? "\(position)/\(total)" : nil }

    var aggregate: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, (Double(completed.count) + currentFraction) / Double(total)))
    }

    mutating func apply(_ event: ImportAttemptEvent) {
        switch event {
        case .normalizationStarted(let id):
            guard normalizationIDs.contains(id), !completed.contains(id) else { return }
            if currentID != id { currentID = id; currentFraction = 0 }
        case .normalizationProgress(let id, let fraction):
            guard id == currentID, !completed.contains(id), fraction.isFinite else { return }
            currentFraction = max(currentFraction, min(1, max(0, fraction)))
        case .normalizationFinished(let id):
            guard normalizationIDs.contains(id) else { return }
            completed.insert(id)
            if currentID == id { currentID = nil; currentFraction = 0 }
        case .boundaryChecked, .materializationStarted, .saveImminent:
            break
        }
    }
}

/// The one consolidated exclusion / single-candidate rejection copy (exact accepted wording; no counts).
extension ImportSelectionNotice {
    var title: String {
        switch self {
        case .shortItemsExcluded: return "짧은 영상이 제외되었어요"
        case .longItemsExcluded: return "긴 영상이 제외되었어요"
        case .shortAndLongItemsExcluded, .nonPortraitItemsExcluded, .mixedItemsExcluded: return "일부 영상이 제외되었어요"
        case .invalidOrUnsupportedItemsExcluded: return "일부 영상을 추가할 수 없어요"
        case .candidateBelowMinimum: return "영상이 너무 짧아요"
        case .candidateAboveMaximum: return "영상이 너무 길어요"
        case .candidateInvalidOrUnsupported: return "영상을 추가할 수 없어요"
        case .candidateNonPortrait: return "지원하지 않는 영상이에요"
        }
    }

    var message: String {
        switch self {
        case .shortItemsExcluded: return "1초 미만의 영상은 추가할 수 없어요."
        case .longItemsExcluded: return "5초를 초과한 영상은 추가할 수 없어요."
        case .shortAndLongItemsExcluded: return "1초 미만이거나 5초를 초과한 영상은 추가할 수 없어요."
        case .invalidOrUnsupportedItemsExcluded: return "읽을 수 없거나 지원하지 않는 영상은 제외되었어요."
        case .nonPortraitItemsExcluded: return "세로 형식이 아닌 영상은 추가할 수 없어요."
        case .mixedItemsExcluded: return "길이 조건에 맞지 않거나 사용할 수 없는 영상은 추가할 수 없어요."
        case .candidateBelowMinimum: return "1초 이상의 영상을 선택해주세요."
        case .candidateAboveMaximum: return "5초 이하의 영상을 선택해주세요."
        case .candidateInvalidOrUnsupported: return "읽을 수 없거나 지원하지 않는 영상이에요. 다른 영상을 선택해주세요."
        case .candidateNonPortrait: return "세로 영상을 선택해주세요."
        }
    }
}

/// An operation waiting for an explicit `다시 시도` / `취소` (no automatic loop).
enum ImportRetryPrompt: Equatable, Sendable {
    /// ADR-042 R4 §3 runtime preparation failure (incl. C2 / C3 shortage and a confirmed prior state after a thrown save).
    case preparationFailed
    /// 050-C CR shortage before a Retry attempt.
    case storageShortage
    /// D7b §1: the target could not be read — unknown, not proven invalid.
    case targetUnavailable

    var title: String {
        switch self {
        case .preparationFailed: return "영상을 준비하지 못했어요"
        case .storageShortage: return "저장 공간이 부족해요"
        case .targetUnavailable: return "프로젝트를 확인하지 못했어요"
        }
    }

    var message: String {
        switch self {
        case .preparationFailed: return "프로젝트에 변경사항이 저장되지 않았어요. 다시 시도해주세요."
        case .storageShortage: return "기기의 저장 공간을 확보한 후 다시 시도해주세요."
        case .targetUnavailable: return "잠시 후 다시 시도해주세요."
        }
    }

    static let retryAction = "다시 시도"
    static let cancelAction = "취소"

    /// The prompt for an operation waiting on `evidence` (the last eligible attempt outcome).
    static func forEvidence(_ evidence: ImportAttemptOutcome) -> ImportRetryPrompt {
        if case .failedBeforeSave(.target(.unreadable), _) = evidence { return .targetUnavailable }
        return .preparationFailed
    }
}

/// Preparation Sheet copy (ADR-042 Revision 4 §1).
enum ImportPreparationCopy {
    static let title = "영상을 준비하고 있어요"
    static let message = "잠시만 기다려주세요."
    static let cancelAction = "취소"
}
