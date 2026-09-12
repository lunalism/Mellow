import XCTest
@testable import Mellow

final class DomainModelsTests: XCTestCase {
    func testTenSecondClipIsAccepted() throws {
        let clip = try makeClip(duration: .seconds(10))

        XCTAssertEqual(clip.effectiveDuration, ClipPolicy.maximumDuration)
    }

    func testClipLongerThanTenSecondsIsRejected() throws {
        let duration = try MediaTime(value: 6_001, timescale: 600)

        XCTAssertThrowsError(try makeClip(duration: duration)) { error in
            XCTAssertEqual(error as? DomainValidationError, .clipDurationExceedsMaximum)
        }
    }

    func testZeroDurationClipIsRejected() {
        XCTAssertThrowsError(try makeClip(duration: .zero)) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidClipDuration)
        }
    }

    func testNegativeDurationClipIsRejected() throws {
        let negativeDuration = try MediaTime(value: -1, timescale: 1)

        XCTAssertThrowsError(try makeClip(duration: negativeDuration)) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidClipDuration)
        }
    }

    func testPortraitOrientationIsRepresented() throws {
        let project = try VlogProject(orientation: .portrait9x16)

        XCTAssertEqual(project.orientation, .portrait9x16)
    }

    func testLandscapeOrientationIsRepresented() throws {
        let project = try VlogProject(orientation: .landscape16x9)

        XCTAssertEqual(project.orientation, .landscape16x9)
    }

    func testProjectDurationSumsEffectiveClipDurations() throws {
        let projectID = UUID()
        let project = try VlogProject(
            id: projectID,
            orientation: .portrait9x16,
            clips: [
                try makeClip(projectID: projectID, duration: .seconds(3), sortOrder: 0),
                try makeClip(projectID: projectID, duration: .seconds(7), sortOrder: 1)
            ]
        )

        XCTAssertEqual(project.totalDuration, .seconds(10))
    }

    func testReorderChangesLogicalClipOrderAndReindexesSortOrder() throws {
        let projectID = UUID()
        let first = try makeClip(id: UUID(), projectID: projectID, sortOrder: 0)
        let second = try makeClip(id: UUID(), projectID: projectID, sortOrder: 1)
        let third = try makeClip(id: UUID(), projectID: projectID, sortOrder: 2)
        var project = try VlogProject(
            id: projectID,
            orientation: .portrait9x16,
            clips: [first, second, third]
        )

        try project.reorderClip(id: third.id, toIndex: 0)

        XCTAssertEqual(project.clips.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(project.clips.map(\.sortOrder), [0, 1, 2])
    }

    func testDisplayNameUsesCreatedAtWithLocaleAwareFormatting() throws {
        let createdAt = Date(timeIntervalSince1970: 1_704_164_240)
        let laterDate = createdAt.addingTimeInterval(60 * 60)
        let locale = Locale(identifier: "en_US")
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let project = try VlogProject(
            createdAt: createdAt,
            orientation: .portrait9x16
        )

        let displayName = project.displayName(locale: locale, timeZone: timeZone)

        XCTAssertEqual(
            displayName,
            ProjectDisplayNameFormatter.displayName(
                for: createdAt,
                locale: locale,
                timeZone: timeZone
            )
        )
        XCTAssertNotEqual(
            displayName,
            ProjectDisplayNameFormatter.displayName(
                for: laterDate,
                locale: locale,
                timeZone: timeZone
            )
        )
    }

    func testAbsoluteMediaPathIsRejected() {
        XCTAssertThrowsError(try RelativeMediaPath("/private/clip.mov")) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidMediaRelativePath)
        }
    }

    private func makeClip(
        id: UUID = UUID(),
        projectID: UUID = UUID(),
        duration: MediaTime = .seconds(10),
        sortOrder: Int = 0
    ) throws -> VlogClip {
        try VlogClip(
            id: id,
            projectID: projectID,
            sourceKind: .recorded,
            mediaRelativePath: try RelativeMediaPath("projects/clip-\(id.uuidString).mov"),
            sourceDuration: duration,
            trimDuration: duration,
            sortOrder: sortOrder
        )
    }
}
