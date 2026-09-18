#if DEBUG
import CoreMedia
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Codable, JSON-friendly snapshot of an inspection (CMTime as value/timescale, transform as
/// its six components). Diagnostic only.
struct Phase6SpikeInspectionSnapshot: Codable, Equatable {
    struct Time: Codable, Equatable { var value: Int64; var timescale: Int32; var seconds: Double?; var isNumeric: Bool }
    var fileName: String
    var fileExtension: String
    var byteCount: Int64
    var container: String
    var brands: String
    var isReadable: Bool
    var isPlayable: Bool
    var isExportable: Bool
    var hasProtectedContent: Bool
    var duration: Time
    var hasVideoTrack: Bool
    var videoCodec: String
    var profileDescription: String
    var profileIsHighBitDepth: Bool
    var bitsPerComponent: Int?
    var fullRangeVideo: Bool?
    var naturalWidth: Double
    var naturalHeight: Double
    var transform: [Double]
    var presentationWidth: Double
    var presentationHeight: Double
    var presentationOrientation: String
    var isMirrored: Bool
    var nominalFrameRate: Float
    var minFrameDuration: Time
    var estimatedDataRate: Float
    var variableFrameRateNote: String
    var isVariableFrameRateSuspected: Bool
    var colorPrimaries: String?
    var transferFunction: String?
    var ycbcrMatrix: String?
    var hdrMetadataNotes: [String]
    var hasAudioTrack: Bool
    var audioCodec: String
    var audioSampleRate: Double
    var audioChannels: Int
    var loadError: String?
    var path: String
    var pathReasons: [String]

    static func time(_ t: CMTime) -> Time { Time(value: t.value, timescale: t.timescale, seconds: t.isNumeric ? t.seconds : nil, isNumeric: t.isNumeric) }

    init(_ i: Phase6SpikeMediaInfo) {
        fileName = i.displayName; fileExtension = i.fileExtension; byteCount = i.byteCount
        container = i.container.rawValue; brands = i.brands
        isReadable = i.isReadable; isPlayable = i.isPlayable; isExportable = i.isExportable; hasProtectedContent = i.hasProtectedContent
        duration = Self.time(i.duration)
        hasVideoTrack = i.hasVideoTrack; videoCodec = i.videoCodec; profileDescription = i.profileDescription; profileIsHighBitDepth = i.profileIsHighBitDepth
        bitsPerComponent = i.bitsPerComponent; fullRangeVideo = i.fullRangeVideo
        naturalWidth = i.naturalSize.width; naturalHeight = i.naturalSize.height
        let t = i.preferredTransform; transform = [t.a, t.b, t.c, t.d, t.tx, t.ty]
        presentationWidth = i.presentationSize.width; presentationHeight = i.presentationSize.height
        presentationOrientation = i.presentationOrientation; isMirrored = i.isMirrored
        nominalFrameRate = i.nominalFrameRate; minFrameDuration = Self.time(i.minFrameDuration); estimatedDataRate = i.estimatedDataRate
        variableFrameRateNote = i.variableFrameRateNote; isVariableFrameRateSuspected = i.isVariableFrameRateSuspected
        colorPrimaries = i.colorPrimaries; transferFunction = i.transferFunction; ycbcrMatrix = i.ycbcrMatrix; hdrMetadataNotes = i.hdrMetadataNotes
        hasAudioTrack = i.hasAudioTrack; audioCodec = i.audioCodec; audioSampleRate = i.audioSampleRate; audioChannels = i.audioChannels
        loadError = i.loadError; path = i.path.rawValue; pathReasons = i.pathReasons
    }
}

/// One durable record per attempted run. Written atomically to `results/<run-id>.json`.
/// Schema 2 added only optional fields (deterministic cancellation / source-integrity evidence) and
/// schema 3 adds only the optional SDR output-contract result, so schema-1 / schema-2 records
/// written by earlier builds keep decoding unchanged.
struct Phase6SpikeRunRecord: Codable, Equatable {
    static let currentSchemaVersion = 3
    static let capacitySamplingWarning = "Capacity / footprint / thermal are sampled every pollingIntervalSeconds; measuredTemporaryDeltaBytes is a LOWER BOUND, not the instantaneous storage peak. An unchanged capacity reading does not prove zero temporary allocation."

    var schemaVersion = currentSchemaVersion
    var runID: UUID
    var startedAt: Date
    var endedAt: Date
    var sourceFileName: String
    var sourceItemID: UUID
    var outputFileName: String?
    var intendedPath: String            // copy / normalize (ADR-044: no remux route)
    var classificationPath: String
    var classificationReasons: [String]
    var sourceSnapshot: Phase6SpikeInspectionSnapshot
    var outputSnapshot: Phase6SpikeInspectionSnapshot?
    var succeeded: Bool
    var cancelled: Bool
    var readerStatus: String
    var writerStatus: String
    var errorDomain: String?
    var errorCode: Int?
    var errorMessage: String?
    var elapsedSeconds: Double
    var videoSamples: Int
    var audioSamples: Int
    var progressReached: Double
    var thermalBefore: String
    var thermalPeak: String
    var thermalAfter: String
    var footprintBeforeBytes: Int64
    var footprintPeakBytes: Int64
    var footprintAfterBytes: Int64
    var capacityBeforeBytes: Int64
    var capacityMinimumDuringBytes: Int64
    var capacityAfterBytes: Int64
    var measuredTemporaryDeltaBytes: Int64
    var pollingIntervalSeconds: Double
    var capacitySamplingWarning = capacitySamplingWarning
    var sourceBytes: Int64
    var outputBytes: Int64
    var partialOutputExistedAfterCancel: Bool?
    var cleanupSucceeded: Bool?
    var leftoverFiles: [String]
    var pipelineNotes: [String]
    var deviceModel: String
    var deviceIdentifier: String
    var systemName: String
    var systemVersion: String
    var appVersion: String
    var appBuild: String
    // Schema 2 (all optional — absent in schema-1 files).
    var autoCancelEnabled: Bool?
    var autoCancelThreshold: Double?
    var cancellationSource: String?
    var cancellationRequestedProgress: Double?
    var cancellationRequestedAt: Date?
    var cancellationRequestCount: Int?
    var outputCandidateFileName: String?
    var outputExistsAfterCleanup: Bool?
    var runLeftoverFiles: [String]?
    var sourceBytesAfter: Int64?
    var sourceModificationBefore: Date?
    var sourceModificationAfter: Date?
    var sourceUnchanged: Bool?
    // Schema 3 (optional): diagnostic SDR output contract evaluated on the inspected output.
    var outputIsValidSDR: Bool?
    var outputSDRProblems: [String]?

    var outcomeLabel: String { cancelled ? "cancelled" : (succeeded ? "success" : "failure") }
}

/// Environment facts through public APIs only.
enum Phase6SpikeEnvironment {
    static func deviceModel() -> String {
        #if canImport(UIKit)
        return UIDevice.current.model
        #else
        return "unknown"
        #endif
    }
    static func deviceIdentifier() -> String {
        var system = utsname(); uname(&system)
        return withUnsafePointer(to: &system.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
    }
    static func systemName() -> String {
        #if canImport(UIKit)
        return UIDevice.current.systemName
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }
    static func systemVersion() -> String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        let v = ProcessInfo.processInfo.operatingSystemVersion; return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #endif
    }
    static func appVersion() -> String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "-" }
    static func appBuild() -> String { (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "-" }
}

/// Reads and atomically writes run records inside the spike `results/` directory. Failures are
/// returned as values so a logging problem can never alter or abort a conversion.
struct Phase6SpikeResultStore {
    let directory: Phase6SpikeDirectory

    enum ListedRecord: Equatable {
        case record(Phase6SpikeRunRecord, fileName: String)
        case unreadable(fileName: String, reason: String)
        var fileName: String { switch self { case .record(_, let f), .unreadable(let f, _): return f } }
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    func url(for record: Phase6SpikeRunRecord) -> URL {
        directory.resultsDirectory.appendingPathComponent(record.runID.uuidString).appendingPathExtension("json")
    }

    /// Temp file inside `results/` → atomic rename over the final name. Returns the error instead
    /// of throwing so callers can log and continue.
    @discardableResult
    func write(_ record: Phase6SpikeRunRecord) -> Error? {
        do {
            try directory.prepare()
            let final = url(for: record)
            guard directory.owns(final) else { return CocoaError(.fileWriteInvalidFileName) }
            let temporary = directory.resultsDirectory.appendingPathComponent(".\(record.runID.uuidString).json.tmp")
            let data = try Self.encoder().encode(record)
            try data.write(to: temporary, options: [.atomic])
            if FileManager.default.fileExists(atPath: final.path) {
                _ = try FileManager.default.replaceItemAt(final, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: final)
            }
            return nil
        } catch {
            return error
        }
    }

    /// Every `*.json` in `results/`, newest first; unreadable / corrupt files are surfaced, never thrown.
    func list() -> [ListedRecord] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: directory.resultsDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var out: [(Date, ListedRecord)] = []
        for url in urls where url.pathExtension == "json" && !url.lastPathComponent.hasPrefix(".") {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            do {
                let record = try Self.decoder().decode(Phase6SpikeRunRecord.self, from: Data(contentsOf: url))
                out.append((record.endedAt, .record(record, fileName: url.lastPathComponent)))
            } catch {
                out.append((date, .unreadable(fileName: url.lastPathComponent, reason: error.localizedDescription)))
            }
        }
        return out.sorted { $0.0 > $1.0 }.map(\.1)
    }
}

extension Phase6SpikeRunRecord {
    /// Builds the durable record from the in-memory result and snapshots.
    static func make(runID: UUID, startedAt: Date, endedAt: Date, source: Phase6SpikeMediaInfo, output: Phase6SpikeMediaInfo?, intendedPath: String, result: Phase6SpikeResult, progressReached: Double, pollingInterval: Double, leftovers: [String]) -> Phase6SpikeRunRecord {
        var errorDomain: String?, errorCode: Int?, errorMessage: String?
        if let e = result.errorDescription {
            errorMessage = e
            if let slash = e.firstIndex(of: "/"), let colon = e.firstIndex(of: ":"), slash < colon {
                errorDomain = String(e[..<slash]); errorCode = Int(e[e.index(after: slash)..<colon])
            }
        }
        return Phase6SpikeRunRecord(
            runID: runID, startedAt: startedAt, endedAt: endedAt,
            sourceFileName: source.displayName, sourceItemID: source.id,
            outputFileName: result.succeeded && !result.cancelled ? result.outputURL.lastPathComponent : nil,
            intendedPath: intendedPath, classificationPath: source.path.rawValue, classificationReasons: source.pathReasons,
            sourceSnapshot: Phase6SpikeInspectionSnapshot(source), outputSnapshot: result.cancelled ? nil : output.map(Phase6SpikeInspectionSnapshot.init),
            succeeded: result.succeeded, cancelled: result.cancelled, readerStatus: result.readerStatus, writerStatus: result.writerStatus,
            errorDomain: errorDomain, errorCode: errorCode, errorMessage: errorMessage,
            elapsedSeconds: result.elapsed, videoSamples: result.videoSamples, audioSamples: result.audioSamples, progressReached: progressReached,
            thermalBefore: Phase6SpikeMetrics.thermalName(result.thermalBefore), thermalPeak: Phase6SpikeMetrics.thermalName(result.thermalPeak), thermalAfter: Phase6SpikeMetrics.thermalName(result.thermalAfter),
            footprintBeforeBytes: result.footprintBefore, footprintPeakBytes: result.footprintPeak, footprintAfterBytes: result.footprintAfter,
            capacityBeforeBytes: result.capacityBefore, capacityMinimumDuringBytes: result.capacityMinimumDuring, capacityAfterBytes: result.capacityAfter,
            measuredTemporaryDeltaBytes: result.peakTemporaryDelta, pollingIntervalSeconds: pollingInterval,
            sourceBytes: result.sourceBytes, outputBytes: result.outputBytes,
            partialOutputExistedAfterCancel: result.partialOutputExistedAfterCancel, cleanupSucceeded: result.cleanupSucceeded,
            leftoverFiles: leftovers, pipelineNotes: result.notes,
            deviceModel: Phase6SpikeEnvironment.deviceModel(), deviceIdentifier: Phase6SpikeEnvironment.deviceIdentifier(),
            systemName: Phase6SpikeEnvironment.systemName(), systemVersion: Phase6SpikeEnvironment.systemVersion(),
            appVersion: Phase6SpikeEnvironment.appVersion(), appBuild: Phase6SpikeEnvironment.appBuild(),
            autoCancelEnabled: result.autoCancelThreshold != nil, autoCancelThreshold: result.autoCancelThreshold,
            cancellationSource: result.cancellationSource, cancellationRequestedProgress: result.cancellationRequestedProgress,
            cancellationRequestedAt: result.cancellationRequestedAt, cancellationRequestCount: result.cancellationRequestCount,
            outputCandidateFileName: result.outputURL.lastPathComponent, outputExistsAfterCleanup: result.outputExistsAfterCleanup,
            runLeftoverFiles: leftovers.filter { $0.contains(source.id.uuidString) || $0.contains(runID.uuidString) },
            sourceBytesAfter: result.sourceBytesAfter >= 0 ? result.sourceBytesAfter : nil,
            sourceModificationBefore: result.sourceModificationBefore, sourceModificationAfter: result.sourceModificationAfter,
            sourceUnchanged: result.sourceUnchanged,
            outputIsValidSDR: result.cancelled ? nil : output.map { $0.sdrOutputProblems.isEmpty },
            outputSDRProblems: result.cancelled ? nil : output.map(\.sdrOutputProblems))
    }
}
#endif
