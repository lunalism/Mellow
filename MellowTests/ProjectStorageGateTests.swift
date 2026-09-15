import XCTest
@testable import Mellow

/// Approved Phase-5 Project Bootstrap Materialization storage gate (ADR-024 technical resolution).
final class ProjectStorageGateTests: XCTestCase {
    private let reserve = ProjectCompositionPolicy.materializationSafetyReserveBytes

    func testApprovedReserveIsExactly100MiB() {
        XCTAssertEqual(reserve, 104_857_600)
        XCTAssertEqual(reserve, 100 * 1_024 * 1_024, "binary MiB, not decimal MB")
    }

    func testReserveIsSpecificToPhase5BootstrapNotRecording() {
        XCTAssertEqual(RecordingPolicy.minimumUsableStorageBytes, 200 * 1_024 * 1_024, "Phase-4 recording gate unchanged")
        XCTAssertNotEqual(reserve, RecordingPolicy.minimumUsableStorageBytes)
    }

    func testRequiredIsAdditionalPlusReserve() {
        XCTAssertEqual(VolumeProjectStorageGate.requiredBytes(additionalBytes: 0, safetyReserveBytes: reserve), reserve)
        XCTAssertEqual(VolumeProjectStorageGate.requiredBytes(additionalBytes: 12_345, safetyReserveBytes: reserve), reserve + 12_345)
    }

    func testBootstrapEstimateIsZeroBecauseAdoptedBytesAlreadyOccupyTheVolume() {
        XCTAssertEqual(ProjectCompositionPolicy.estimatedPeakAdditionalBytes(adoptedSourceBytes: 0), 0)
        XCTAssertEqual(ProjectCompositionPolicy.estimatedPeakAdditionalBytes(adoptedSourceBytes: 750_000_000), 0, "no double count, no multiplier")
    }

    private func verdict(usable: Int64, additional: Int64 = 0) async -> ProjectStorageVerdict {
        await VolumeProjectStorageGate(capacity: { usable }, safetyReserveBytes: reserve).check(additionalBytes: additional)
    }

    func testSufficientInsufficientAndBoundary() async {
        let above = await verdict(usable: reserve + 1)
        XCTAssertEqual(above, .sufficient)
        let equal = await verdict(usable: reserve)
        XCTAssertEqual(equal, .sufficient, "available == required passes")
        let below = await verdict(usable: reserve - 1)
        XCTAssertEqual(below, .insufficient(requiredBytes: reserve, usableBytes: reserve - 1))
        let withAdditional = await verdict(usable: reserve + 999, additional: 1_000)
        XCTAssertEqual(withAdditional, .insufficient(requiredBytes: reserve + 1_000, usableBytes: reserve + 999))
    }

    // MARK: - Pre-copy admission at the Transferable boundary

    func testTransferAdmitStatsIncomingFileAndRefusesBelowRequirement() async throws {
        let incoming = try await TestMediaFixtures.shared.portrait(seconds: 2)
        let size = Int64(try incoming.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        XCTAssertGreaterThan(size, 0, "the received file URL is stat-able before any copy")

        let recording = await MainActor.run { ScriptedCapacityGate(capacities: [size + reserve]) }
        ReceivedVideoFile.admission.set(recording)
        defer { ReceivedVideoFile.admission.set(nil) }
        try await ReceivedVideoFile.admit(incoming)
        let checks = await MainActor.run { recording.checks }
        XCTAssertEqual(checks, [size], "admission uses the exact incoming byte size")

        let refusing = await MainActor.run { ScriptedCapacityGate(capacities: [size + reserve - 1]) }
        ReceivedVideoFile.admission.set(refusing)
        do {
            try await ReceivedVideoFile.admit(incoming)
            XCTFail("must refuse")
        } catch let refusal as ProjectMediaAdmissionRefused {
            XCTAssertEqual(refusal, ProjectMediaAdmissionRefused(requiredBytes: size + reserve, usableBytes: size + reserve - 1))
        }
    }

    func testTransferWithoutPublishedGateIsRefusedNotUngated() async throws {
        let incoming = try await TestMediaFixtures.shared.portrait(seconds: 2)
        ReceivedVideoFile.admission.set(nil)
        do {
            try await ReceivedVideoFile.admit(incoming)
            XCTFail("no gate must never mean a silent pass")
        } catch is ProjectMediaAdmissionRefused {}
    }

    func testUnknownCapacityIsNeverASilentPass() async {
        // The store reports 0 when the volume cannot be inspected.
        let unknown = await verdict(usable: 0)
        XCTAssertEqual(unknown, .insufficient(requiredBytes: reserve, usableBytes: 0))
    }
}
