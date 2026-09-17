import PhotosUI
import SwiftUI
import XCTest
@testable import Mellow

/// Selection isolation of the real PhotosPicker state bridge, tested directly (no Photos access is
/// available here, so a confirmed item can only ever resolve to `.failed` — which is enough to tell
/// "acted on the selection" apart from "cancelled").
@MainActor
final class PhotosVideoSelectorTests: XCTestCase {
    private var root: URL!
    private var store: ProjectMediaStore!
    private let item = PhotosPickerItem(itemIdentifier: "not-a-real-asset")

    override func setUp() {
        root = TestSupport.temporaryRoot("picker-bridge")
        store = ProjectMediaStore(root: root)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func begin(_ selector: PhotosVideoSelector) async throws -> (ProjectMediaWorkspace, Task<ProjectMediaSelectionOutcome, Never>) {
        let workspace = try await store.beginWorkspace()
        let task = Task { await selector.selectVideos(into: workspace, store: store, admission: FakeProjectStorageGate(verdict: .sufficient)) }
        await Task.yield()
        for _ in 0..<50 where !selector.isPresented { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(selector.isPresented)
        return (workspace, task)
    }

    /// ADR-040: the selection bound belongs to the session — set for the host before presentation,
    /// cleared when the session resolves, so a later Add session is unlimited again.
    func testSelectionLimitIsPublishedForTheSessionAndClearedOnResolve() async throws {
        let selector = PhotosVideoSelector()
        XCTAssertNil(selector.maxSelectionCount)
        let workspace = try await store.beginWorkspace()
        let task = Task { await selector.selectVideos(into: workspace, store: store, admission: FakeProjectStorageGate(verdict: .sufficient), selectionLimit: 1) }
        await Task.yield()
        for _ in 0..<50 where !selector.isPresented { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(selector.isPresented)
        XCTAssertEqual(selector.maxSelectionCount, 1, "Replace session: exactly one video")
        selector.isPresented = false
        selector.pickerDismissed()
        let outcome = await task.value
        guard case .cancelled = outcome else { return XCTFail("\(outcome)") }
        XCTAssertNil(selector.maxSelectionCount, "cleared with the session")
        let (_, unlimited) = try await begin(selector)
        XCTAssertNil(selector.maxSelectionCount, "an Add session is unlimited")
        selector.isPresented = false
        selector.pickerDismissed()
        _ = await unlimited.value
    }

    func testCancelWithoutSelectionIsCancelledAndSessionStartsEmpty() async throws {
        let selector = PhotosVideoSelector()
        selector.items = [item] // stale write outside any session: ignored
        let (_, task) = try await begin(selector)
        XCTAssertTrue(selector.items.isEmpty, "a session starts with an empty selection")
        selector.isPresented = false
        selector.pickerDismissed()
        let outcome = await task.value
        guard case .cancelled = outcome else { return XCTFail("\(outcome)") }
    }

    func testBindingWriteWhilePickerOpenDoesNotStartTransfer() async throws {
        let selector = PhotosVideoSelector()
        let (_, task) = try await begin(selector)
        selector.items = [item] // e.g. a tap that updates the binding before any confirmation
        try await Task.sleep(for: .seconds(1))
        XCTAssertTrue(selector.isPresented, "still awaiting the picker's dismissal")
        // Only dismissal with the selection still present counts as confirmation.
        selector.isPresented = false
        selector.pickerDismissed()
        let outcome = await task.value
        guard case .failed = outcome else { return XCTFail("acted on the confirmed selection: \(outcome)") }
    }

    func testPriorConfirmedSessionDoesNotLeakIntoCancelledSession() async throws {
        let selector = PhotosVideoSelector()
        // Session 1: confirmed selection (transfer fails here for lack of Photos access).
        let (_, first) = try await begin(selector)
        selector.items = [item]
        selector.isPresented = false
        selector.pickerDismissed()
        guard case .failed = await first.value else { return XCTFail() }
        XCTAssertTrue(selector.items.isEmpty, "selection cleared after a terminal outcome")

        // Session 2: present again, cancel without confirming anything.
        let (_, second) = try await begin(selector)
        XCTAssertTrue(selector.items.isEmpty)
        selector.isPresented = false
        selector.pickerDismissed()
        let outcome = await second.value
        guard case .cancelled = outcome else { return XCTFail("stale selection reused: \(outcome)") }

        // Session 3: cancel → reopen → a new confirmed selection is acted on normally.
        let (_, third) = try await begin(selector)
        selector.items = [item]
        selector.isPresented = false
        selector.pickerDismissed()
        guard case .failed = await third.value else { return XCTFail() }
    }

    func testDoubleDismissalResolvesOnce() async throws {
        let selector = PhotosVideoSelector()
        let (_, task) = try await begin(selector)
        selector.isPresented = false
        selector.pickerDismissed()
        selector.pickerDismissed()
        guard case .cancelled = await task.value else { return XCTFail() }
        XCTAssertFalse(selector.isPresented)
    }
}
