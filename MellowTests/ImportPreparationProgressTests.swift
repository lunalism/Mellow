import Foundation
import XCTest
@testable import Mellow

/// ADR-050 050-D D7b §5 preparation progress and the accepted import presentation copy (pure).
final class ImportPreparationProgressTests: XCTestCase {
    private let a = ImportCandidateID(), b = ImportCandidateID(), c = ImportCandidateID()

    func testEqualWeightAggregateAndPosition() {
        var progress = ImportPreparationProgress(normalizationIDs: [a, b])
        XCTAssertEqual(progress.aggregate, 0)
        XCTAssertEqual(progress.positionLabel, "1/2")
        progress.apply(.normalizationStarted(a))
        progress.apply(.normalizationProgress(a, 0.5))
        XCTAssertEqual(progress.aggregate, 0.25, accuracy: 1e-9)
        progress.apply(.normalizationFinished(a))
        XCTAssertEqual(progress.aggregate, 0.5, accuracy: 1e-9)
        progress.apply(.normalizationStarted(b))
        XCTAssertEqual(progress.positionLabel, "2/2")
        progress.apply(.normalizationProgress(b, 1))
        XCTAssertEqual(progress.aggregate, 1, accuracy: 1e-9)
        progress.apply(.normalizationFinished(b))
        XCTAssertEqual(progress.aggregate, 1)
        XCTAssertEqual(progress.position, 2)
    }

    func testInvalidLateAndOutOfOrderCallbacksAreClampedOrIgnored() {
        var progress = ImportPreparationProgress(normalizationIDs: [a, b])
        progress.apply(.normalizationProgress(a, 0.9))                 // before start: ignored
        XCTAssertEqual(progress.aggregate, 0)
        progress.apply(.normalizationStarted(a))
        progress.apply(.normalizationProgress(a, 0.6))
        progress.apply(.normalizationProgress(a, 0.3))                 // out of order: never decreases
        XCTAssertEqual(progress.currentFraction, 0.6, accuracy: 1e-9)
        progress.apply(.normalizationProgress(a, 7))                   // clamped
        XCTAssertEqual(progress.currentFraction, 1)
        progress.apply(.normalizationProgress(a, .nan))                // invalid: ignored
        progress.apply(.normalizationProgress(a, -.infinity))
        XCTAssertEqual(progress.currentFraction, 1)
        progress.apply(.normalizationFinished(a))
        progress.apply(.normalizationProgress(a, 0.2))                 // late callback for a finished item
        progress.apply(.normalizationProgress(c, 0.9))                 // unknown item
        progress.apply(.normalizationStarted(c))
        XCTAssertEqual(progress.aggregate, 0.5, accuracy: 1e-9)
        XCTAssertNil(progress.currentID)
    }

    func testSingleItemShowsNoPositionAndReadyOnlyHasNothingToShow() {
        XCTAssertNil(ImportPreparationProgress(normalizationIDs: [a]).positionLabel, "R4 §1: position only for several items")
        let empty = ImportPreparationProgress(normalizationIDs: [])
        XCTAssertEqual(empty.aggregate, 0)
        XCTAssertNil(empty.positionLabel)
    }

    func testRealNormalizerTargetCountAndFraction() throws {
        XCTAssertEqual(WorkingMediaProgress.fraction(afterTarget: 0, of: 60), 1.0 / 60, accuracy: 1e-12)
        XCTAssertEqual(WorkingMediaProgress.fraction(afterTarget: 99, of: 60), 1)
        XCTAssertEqual(WorkingMediaProgress.fraction(afterTarget: -1, of: 60), 0)
        XCTAssertEqual(WorkingMediaProgress.fraction(afterTarget: 3, of: 0), 0)
    }

    func testAcceptedCopyIsExact() {
        XCTAssertEqual(ImportPreparationCopy.title, "영상을 준비하고 있어요")
        XCTAssertEqual(ImportPreparationCopy.message, "잠시만 기다려주세요.")
        XCTAssertEqual(ImportRetryPrompt.preparationFailed.message, "프로젝트에 변경사항이 저장되지 않았어요. 다시 시도해주세요.")
        XCTAssertEqual(ImportRetryPrompt.storageShortage.title, "저장 공간이 부족해요")
        XCTAssertEqual(ImportRetryPrompt.storageShortage.message, "기기의 저장 공간을 확보한 후 다시 시도해주세요.")
        XCTAssertEqual(ImportRetryPrompt.targetUnavailable.title, "프로젝트를 확인하지 못했어요")
        XCTAssertEqual(ImportRetryPrompt.targetUnavailable.message, "잠시 후 다시 시도해주세요.")
        XCTAssertEqual([ImportRetryPrompt.retryAction, ImportRetryPrompt.cancelAction], ["다시 시도", "취소"])
        XCTAssertEqual(ImportSelectionNotice.mixedItemsExcluded.message, "길이 조건에 맞지 않거나 사용할 수 없는 영상은 추가할 수 없어요.")
        XCTAssertEqual(ImportSelectionNotice.nonPortraitItemsExcluded.message, "세로 형식이 아닌 영상은 추가할 수 없어요.")
        XCTAssertEqual(ImportSelectionNotice.candidateBelowMinimum.title, "영상이 너무 짧아요")
        XCTAssertEqual(ImportSelectionNotice.candidateInvalidOrUnsupported.message, "읽을 수 없거나 지원하지 않는 영상이에요. 다른 영상을 선택해주세요.")
        typealias M = ProjectsEntryModel.CompositionMessage
        XCTAssertEqual(M.sourceUnavailableForRetry.title, "영상을 다시 선택해주세요")
        XCTAssertEqual(M.sourceUnavailableForRetry.message, "선택한 영상을 더 이상 사용할 수 없어요.")
        XCTAssertEqual(M.cleanupUnresolved.message, "프로젝트에 변경사항이 저장되지 않았어요. 영상을 다시 선택해주세요.")
    }
}
