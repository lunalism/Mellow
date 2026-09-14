import XCTest
@testable import Mellow

@MainActor
final class ProjectEditorModelTests: XCTestCase {
    private func makeClip(projectID: UUID, seconds: Int64, order: Int) throws -> VlogClip {
        try VlogClip(
            projectID: projectID,
            sourceKind: .recorded,
            mediaRelativePath: try RelativeMediaPath("seed/clip-\(order).mov"),
            sourceDuration: .seconds(seconds),
            trimDuration: .seconds(seconds),
            sortOrder: order
        )
    }

    private func makeProject(clipSeconds: [Int64]) throws -> VlogProject {
        let id = UUID()
        let clips = try clipSeconds.enumerated().map {
            try makeClip(projectID: id, seconds: $0.element, order: $0.offset)
        }
        return try VlogProject(id: id, orientation: .portrait9x16, clips: clips)
    }

    func testLoadsAndHoldsProject() throws {
        let project = try makeProject(clipSeconds: [2, 3])
        let model = ProjectEditorModel(project: project)
        XCTAssertEqual(model.project.id, project.id)
    }

    func testClipsRemainInLogicalSortOrder() throws {
        let project = try makeProject(clipSeconds: [2, 3, 1])
        let model = ProjectEditorModel(project: project)
        XCTAssertEqual(model.orderedClips.map(\.sortOrder), [0, 1, 2])
    }

    func testFirstClipSelectedInitiallyWhenNonEmpty() throws {
        let project = try makeProject(clipSeconds: [2, 3])
        let model = ProjectEditorModel(project: project)
        XCTAssertEqual(model.selectedClipID, project.clips.first?.id)
        XCTAssertEqual(model.selectedClip?.id, project.clips.first?.id)
    }

    func testEmptyProjectHasNoSelection() throws {
        let project = try VlogProject(orientation: .portrait9x16)
        let model = ProjectEditorModel(project: project)
        XCTAssertNil(model.selectedClipID)
        XCTAssertNil(model.selectedClip)
    }

    func testSelectingValidClipUpdatesSelection() throws {
        let project = try makeProject(clipSeconds: [2, 3, 1])
        let model = ProjectEditorModel(project: project)
        let second = project.clips[1].id
        model.select(second)
        XCTAssertEqual(model.selectedClipID, second)
        XCTAssertEqual(model.selectedClip?.id, second)
    }

    func testSelectingUnknownClipIsIgnored() throws {
        let project = try makeProject(clipSeconds: [2, 3])
        let model = ProjectEditorModel(project: project)
        let original = model.selectedClipID
        model.select(UUID())
        XCTAssertEqual(model.selectedClipID, original)
    }

    func testTotalDurationMatchesProject() throws {
        let project = try makeProject(clipSeconds: [2, 3, 1])
        let model = ProjectEditorModel(project: project)
        XCTAssertEqual(model.totalDuration, project.totalDuration)
        XCTAssertEqual(model.totalDuration, .seconds(6))
    }

    func testSelectionDoesNotMutatePersistedProject() throws {
        let repository = InMemoryProjectRepository()
        let project = try makeProject(clipSeconds: [2, 3])
        try repository.create(project)
        let model = ProjectEditorModel(project: project)

        model.select(project.clips[1].id)

        // Selection is view-only state; the persisted project is untouched.
        let reloaded = try repository.project(id: project.id)
        XCTAssertEqual(reloaded?.clips.map(\.id), project.clips.map(\.id))
        XCTAssertEqual(reloaded?.updatedAt, project.updatedAt)
    }
}
