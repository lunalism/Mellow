#if DEBUG
import AVKit
import CoreTransferable
import Observation
import OSLog
import PhotosUI
import SwiftUI

/// Picker transfer into the spike-owned `sources/` directory (never Photos, never Project media).
/// The provider URL is valid only inside this closure, so the copy is the ONLY URL kept afterwards.
struct Phase6SpikeReceivedFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let directory = Phase6SpikeDirectory.default()
            try directory.prepare()
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = directory.sourcesDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Phase6SpikeReceivedFile(url: destination)
        }
    }
}

@Observable
@MainActor
final class Phase6MediaSpikeModel {
    let directory = Phase6SpikeDirectory.default()
    var pickerItems: [PhotosPickerItem] = []
    var items: [Phase6SpikeMediaInfo] = []
    /// Outputs found in the spike directory at launch (restored from an earlier session).
    var restoredOutputs: [Phase6SpikeMediaInfo] = []
    var selectedID: UUID?
    var isImporting = false
    var isRunning = false
    var progress = Phase6SpikeProgress()
    var results: [Phase6SpikeResult] = []
    var outputInfo: Phase6SpikeMediaInfo?
    var log: [String] = ["진단 전용 화면입니다. 실제 Project / Clip / Photos 원본은 건드리지 않습니다."]
    var cleanupSummary = "-"
    let playback = Phase6SpikePlaybackController()
    var playbackPresented = false
    /// Durable run records (`results/*.json`), newest first; unreadable files are listed as such.
    var savedRecords: [Phase6SpikeResultStore.ListedRecord] = []
    var resultStore: Phase6SpikeResultStore { Phase6SpikeResultStore(directory: directory) }
    static let pollingInterval: Double = 0.25
    /// Picker encoding policy. `.current` asks Photos for the ORIGINAL representation (e.g. HEVC
    /// 10-bit HDR / Dolby Vision `.mov`). The default `.automatic` lets Photos hand over a
    /// compatibility H.264 Rec.709 transcode, which would hide HDR from the inspector entirely.
    /// Production (`ProjectsEntryView` / `ProjectEditorView`) already uses `.current`.
    static let pickerEncoding: PhotosPickerItem.EncodingDisambiguationPolicy = .current
    private var runningTask: Task<Void, Never>?
    /// Deterministic cancellation test mode (DEBUG diagnostic only). Default OFF; when ON, a
    /// normalization run auto-cancels through the shared token at the first progress >= 35%.
    var autoCancelAtThresholdEnabled = false
    /// The token of the run in flight; the manual `취소` button and auto-cancel both use it.
    private(set) var activeCancellation: Phase6SpikeCancellationToken?

    var selected: Phase6SpikeMediaInfo? { items.first { $0.id == selectedID } }
    /// The conversion control is enabled only for a path the converter / copier may actually run.
    var canStartConversion: Bool {
        guard !isRunning, let selected else { return false }
        return selected.path.mayRunMediaOperation
    }
    /// Auto-cancel applies only to a normalization-required QuickTime source.
    var canArmAutoCancel: Bool { selected?.path == .normalizeH264 }
    var selectedIndex: Int? { items.firstIndex { $0.id == selectedID } }

    /// Re-lists files left by an earlier session (sources → items, outputs → restoredOutputs) so a
    /// relaunch can inspect and play them without reselecting. Nothing is moved or deleted.
    func restoreExistingFiles() {
        savedRecords = resultStore.list()
        guard items.isEmpty, restoredOutputs.isEmpty else { return }
        let fm = FileManager.default
        let sources = ((try? fm.contentsOfDirectory(at: directory.sourcesDirectory, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
        let outputs = ((try? fm.contentsOfDirectory(at: directory.outputsDirectory, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !sources.isEmpty || !outputs.isEmpty else { return }
        isImporting = true
        Task {
            for url in sources { let info = await Phase6SpikeInspector.inspect(url); items.append(info); log.append("restored source \(info.displayName): \(info.path.rawValue)") }
            for url in outputs { let info = await Phase6SpikeInspector.inspect(url); restoredOutputs.append(info); log.append("restored output \(info.displayName)") }
            if selectedID == nil { selectedID = items.first?.id }
            if outputInfo == nil { outputInfo = restoredOutputs.last }
            isImporting = false
        }
    }

    func handlePickerSelection() {
        let picked = pickerItems
        pickerItems = []
        guard !picked.isEmpty else { return }
        isImporting = true
        log.append("picker encoding: \(Self.pickerEncoding == .current ? "current (original representation)" : "automatic (system may substitute a compatibility transcode)")")
        Task {
            for item in picked {
                do {
                    guard let received = try await item.loadTransferable(type: Phase6SpikeReceivedFile.self) else { log.append("transfer returned nil"); continue }
                    let info = await Phase6SpikeInspector.inspect(received.url)
                    items.append(info)
                    log.append("inspected \(info.displayName): \(info.path.rawValue)")
                } catch {
                    log.append("transfer failed: \(error.localizedDescription)")
                }
            }
            if selectedID == nil { selectedID = items.first?.id }
            isImporting = false
        }
    }

    func startConversion() {
        guard !isRunning, let item = selected else { return }
        switch item.path {
        case .readyQuickTimeFastPath:
            log.append("\(item.displayName): ready QuickTime — copying as the fast-path diagnostic result (no re-encode)")
            copyFastPath(item); return
        case .normalizeH264: break
        case .preflightInvalid:
            log.append("\(item.displayName): preflight invalid — conversion refused"); return
        case .preflightUnsupportedContainer:
            log.append("\(item.displayName): non-QuickTime container — unsupported (ADR-044), no copy / normalization, no output"); return
        case .preflightUnsupportedNonPortrait:
            log.append("\(item.displayName): non-portrait presentation — unsupported (ADR-043), no copy / normalization"); return
        }
        try? directory.prepare()
        let output = directory.outputsDirectory.appendingPathComponent("\(item.id.uuidString)-h264.mov")
        isRunning = true
        progress = Phase6SpikeProgress(stage: "starting")
        outputInfo = nil
        let runID = UUID(), startedAt = Date()
        let token = Phase6SpikeCancellationToken()
        activeCancellation = token
        let threshold: Double? = autoCancelAtThresholdEnabled ? Phase6SpikeAutoCancel.threshold : nil
        let converter = Phase6SpikeConverter(source: item.url, output: output, cancellation: token, autoCancelThreshold: threshold) { [weak self] snapshot in
            Task { @MainActor in self?.progress = snapshot }
        }
        MellowLog.app.info("Phase6MediaSpike: normalization start autoCancel=\(threshold.map { "\($0)" } ?? "off", privacy: .public)")
        if let threshold { log.append(String(format: "취소 시험 ON: 진행률 %.0f%%에서 자동 취소 (수동 취소와 같은 경로)", threshold * 100)) }
        runningTask = Task.detached { [weak self] in
            let result = await converter.run()
            await MainActor.run {
                guard let self else { return }
                self.finishRun(result: result, item: item, runID: runID, startedAt: startedAt, intendedPath: "normalize")
            }
        }
    }

    /// Single completion path for a normalization run. A cancelled or failed result never
    /// inspects, restores or publishes an output; only a genuine success does.
    func finishRun(result: Phase6SpikeResult, item: Phase6SpikeMediaInfo, runID: UUID, startedAt: Date, intendedPath: String) {
        results.append(result)
        isRunning = false
        activeCancellation = nil
        log.append("\(result.mode): success=\(result.succeeded) cancelled=\(result.cancelled) reader=\(result.readerStatus) writer=\(result.writerStatus) elapsed=\(String(format: "%.2f", result.elapsed))s")
        if let error = result.errorDescription { log.append("error: \(error)") }
        if result.cancelled {
            log.append("cancelled (\(result.cancellationSource ?? "?") at \(result.cancellationRequestedProgress.map { String(format: "%.3f", $0) } ?? "?")): partial output existed=\(result.partialOutputExistedAfterCancel.map(String.init) ?? "?") cleanup ok=\(result.cleanupSucceeded.map(String.init) ?? "?") exists after cleanup=\(result.outputExistsAfterCleanup.map(String.init) ?? "?") source unchanged=\(result.sourceUnchanged.map(String.init) ?? "?") leftovers=\(directory.leftovers().count)")
        }
        let progress = self.progress.fraction
        Task { @MainActor in
            var output: Phase6SpikeMediaInfo?
            if result.succeeded && !result.cancelled { output = await self.inspectOutput(result.outputURL) }
            self.persistRecord(runID: runID, startedAt: startedAt, source: item, output: output, intendedPath: intendedPath, result: result, progressReached: progress)
        }
    }

    /// Writes the durable JSON record; a logging failure is only logged and never changes the
    /// represented result (the in-memory `results` entry is already appended).
    func persistRecord(runID: UUID, startedAt: Date, source: Phase6SpikeMediaInfo, output: Phase6SpikeMediaInfo?, intendedPath: String, result: Phase6SpikeResult, progressReached: Double) {
        let record = Phase6SpikeRunRecord.make(runID: runID, startedAt: startedAt, endedAt: Date(), source: source, output: output, intendedPath: intendedPath, result: result, progressReached: progressReached, pollingInterval: Self.pollingInterval, leftovers: directory.leftovers())
        if let error = resultStore.write(record) {
            log.append("측정 기록 저장 실패(결과에는 영향 없음): \(error.localizedDescription)")
        } else {
            log.append("측정 기록 저장: \(record.runID.uuidString).json")
        }
        savedRecords = resultStore.list()
    }

    private func copyFastPath(_ item: Phase6SpikeMediaInfo) {
        try? directory.prepare()
        let output = directory.outputsDirectory.appendingPathComponent("\(item.id.uuidString)-copy.mov")
        try? FileManager.default.removeItem(at: output)
        do {
            let start = Date()
            try FileManager.default.copyItem(at: item.url, to: output)
            var result = Phase6SpikeResult(mode: "fast path copy", outputURL: output)
            result.succeeded = true; result.elapsed = Date().timeIntervalSince(start)
            result.sourceBytes = item.byteCount
            result.outputBytes = Int64((try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            results.append(result)
            let startedAt = start
            Task { @MainActor in
                let info = await self.inspectOutput(output)
                self.persistRecord(runID: UUID(), startedAt: startedAt, source: item, output: info, intendedPath: "copy", result: result, progressReached: 1)
            }
        } catch {
            log.append("copy failed: \(error.localizedDescription)")
            var result = Phase6SpikeResult(mode: "fast path copy", outputURL: output)
            result.errorDescription = "\((error as NSError).domain)/\((error as NSError).code): \(error.localizedDescription)"
            result.sourceBytes = item.byteCount
            persistRecord(runID: UUID(), startedAt: Date(), source: item, output: nil, intendedPath: "copy", result: result, progressReached: 0)
        }
    }

    /// Unit-test seam only: lets a test observe that `cancel()` reaches the shared token.
    func setActiveCancellationForTesting(_ token: Phase6SpikeCancellationToken) { activeCancellation = token }

    /// Manual cancellation: the same token the deterministic auto-cancel uses (idempotent), plus
    /// task cancellation as a belt-and-braces signal. Safe to call repeatedly or after completion.
    func cancel() {
        guard isRunning, let token = activeCancellation else { return }
        let first = token.requestCancel(source: .manual, progress: progress.fraction)
        log.append(first ? "취소 요청 (manual)" : "취소 요청 (already cancelled by \(token.source?.rawValue ?? "?"), request #\(token.requestCount))")
        runningTask?.cancel()
    }

    @discardableResult
    private func inspectOutput(_ url: URL) async -> Phase6SpikeMediaInfo {
        let info = await Phase6SpikeInspector.inspect(url)
        outputInfo = info
        if !restoredOutputs.contains(where: { $0.url == url }) { restoredOutputs.append(info) }
        log.append("output: \(info.container.rawValue) \(info.videoCodec) \(Int(info.presentationSize.width))×\(Int(info.presentationSize.height)) \(info.transferFunction ?? "untagged") \(Phase6SpikeFormat.bytes(info.byteCount)) — SDR contract: \(info.sdrOutputProblems.isEmpty ? "VALID" : info.sdrOutputProblems.joined(separator: " | "))")
        return info
    }

    /// Opens the diagnostic player on a spike-owned file (source copy or completed output).
    func openPlayback(_ target: Phase6SpikePlaybackTarget) {
        let ok = playback.open(target)
        log.append("player open \(target.label) \(target.url.lastPathComponent): \(ok ? "ok" : (playback.loadError ?? "failed"))")
        playbackPresented = true
    }

    func closePlayback() {
        playback.close()
        playbackPresented = false
    }

    func cleanupDiagnosticFiles() {
        guard !isRunning else { cleanupSummary = "변환 중에는 정리하지 않습니다"; return }
        closePlayback()
        let leftovers = directory.leftovers()
        let outcome = directory.cleanup()
        items = []; restoredOutputs = []; selectedID = nil; outputInfo = nil; results = []; savedRecords = []
        cleanupSummary = "removed=\(outcome.removed) error=\(outcome.error?.localizedDescription ?? "none") (had \(leftovers.count) entries); root exists now: \(FileManager.default.fileExists(atPath: directory.root.path))"
        log.append("진단 파일 정리: \(cleanupSummary)")
    }
}

/// DEBUG-only diagnostic surface, reachable only via the `-Phase6MediaSpike` launch argument.
struct Phase6MediaSpikeView: View {
    @State private var model = Phase6MediaSpikeModel()
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section("진단 (DEBUG · Phase 6 Technical Spike)") {
                    Text("이 화면은 진단 전용입니다. Project / Clip / Photos 원본을 변경하지 않으며 결과는 `\(Phase6SpikeDirectory.componentName)` 안에만 저장됩니다.").font(.footnote).foregroundStyle(.secondary)
                    Button("Photos에서 영상 선택") { showPicker = true }.buttonStyle(.borderless).disabled(model.isRunning || model.isImporting)
                    if model.isImporting { ProgressView("가져오는 중…") }
                }
                Section("선택 항목 (\(model.items.count))") {
                    ForEach(model.items) { item in
                        DisclosureGroup(isExpanded: .constant(model.selectedID == item.id)) {
                            ForEach(Array(item.report.enumerated()), id: \.offset) { row in
                                VStack(alignment: .leading, spacing: 2) { Text(row.element.0).font(.caption2).foregroundStyle(.secondary); Text(row.element.1).font(.caption.monospaced()) }
                            }
                        } label: {
                            HStack {
                                Image(systemName: model.selectedID == item.id ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading) { Text(item.displayName).font(.subheadline); Text(item.path.rawValue).font(.caption).foregroundStyle(.secondary) }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { model.selectedID = item.id }
                        }
                    }
                }
                Section("변환") {
                    // Borderless: a List row with several default-style buttons fires every button on a row tap.
                    HStack {
                        Button("변환 시작") { model.startConversion() }.buttonStyle(.borderless).disabled(!model.canStartConversion)
                        Spacer()
                        Button("취소", role: .destructive) { model.cancel() }.buttonStyle(.borderless).disabled(!model.isRunning)
                    }
                    if let index = model.selectedIndex { Text("현재 항목 \(index + 1)/\(model.items.count)").font(.caption) }
                    if let selected = model.selected, selected.path == .preflightUnsupportedNonPortrait {
                        Text("이 항목은 세로 형식이 아닌 Presentation(가로 / 정사각형)이라 ADR-043에 따라 Preflight에서 제외됩니다. 복사 / 정규화 / 변환을 수행하지 않습니다.").font(.caption).foregroundStyle(.red)
                    }
                    if let selected = model.selected, selected.path == .preflightUnsupportedContainer {
                        Text("이 항목의 실제 컨테이너가 QuickTime Movie가 아니라(MP4 / 기타 / 불명) ADR-044에 따라 Preflight에서 제외됩니다. 복사 / 정규화 / Remux를 수행하지 않으며 출력 파일을 만들지 않습니다. (확장자는 판정에 쓰이지 않음)").font(.caption).foregroundStyle(.red)
                    }
                    Toggle("취소 시험: 진행률 35%에서 자동 취소", isOn: $model.autoCancelAtThresholdEnabled)
                        .disabled(model.isRunning || !model.canArmAutoCancel)
                        .font(.subheadline)
                    Text(model.canArmAutoCancel ? "ON이면 실제 정규화 파이프라인을 시작한 뒤 샘플 기반 진행률이 처음 35% 이상이 되는 순간 수동 취소와 같은 경로로 취소합니다. OFF(기본)면 아무 영향이 없습니다." : "정규화가 필요한 QuickTime 항목을 선택했을 때만 사용할 수 있습니다.").font(.caption2).foregroundStyle(.secondary)
                    if model.isRunning || model.progress.stage != "idle" {
                        ProgressView(value: model.progress.fraction) { Text("\(model.progress.stage) · \(Int(model.progress.fraction * 100))%") }
                        Text(String(format: "경과 %.1fs · thermal %@ · footprint %@ · free %@", model.progress.elapsed, Phase6SpikeMetrics.thermalName(model.progress.thermal), Phase6SpikeFormat.bytes(model.progress.footprintBytes), Phase6SpikeFormat.bytes(model.progress.freeCapacityBytes))).font(.caption.monospaced())
                    }
                }
                if let result = model.results.last {
                    Section("측정 결과 (\(result.mode))") { resultRows(result) }
                }
                if let output = model.outputInfo {
                    Section("출력 검사") {
                        ForEach(Array(output.report.enumerated()), id: \.offset) { row in
                            VStack(alignment: .leading, spacing: 2) { Text(row.element.0).font(.caption2).foregroundStyle(.secondary); Text(row.element.1).font(.caption.monospaced()) }
                        }
                    }
                }
                Section("A/B 재생 (메타데이터만으로 HDR 정확성을 판단하지 않습니다)") {
                    if let source = model.selected {
                        Button("원본 재생 열기 · \(source.displayName)") { model.openPlayback(.source(source.url)) }.buttonStyle(.borderless)
                    } else { Text("원본: 선택 항목 없음").font(.caption).foregroundStyle(.secondary) }
                    if model.restoredOutputs.isEmpty { Text("변환 결과: 없음").font(.caption).foregroundStyle(.secondary) }
                    ForEach(model.restoredOutputs) { output in
                        Button("변환 결과 재생 열기 · \(output.displayName)") { model.openPlayback(.output(output.url)) }.buttonStyle(.borderless)
                    }
                }
                Section("저장된 측정 기록 (\(model.savedRecords.count))") {
                    if model.savedRecords.isEmpty { Text("기록 없음").font(.caption).foregroundStyle(.secondary) }
                    ForEach(Array(model.savedRecords.enumerated()), id: \.offset) { entry in
                        switch entry.element {
                        case .record(let r, _):
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(r.endedAt.formatted(date: .abbreviated, time: .standard)) · \(r.sourceFileName)").font(.caption.monospaced())
                                Text("\(r.intendedPath) · \(r.outcomeLabel) · \(String(format: "%.2f s", r.elapsedSeconds)) · 기록 파일 있음").font(.caption2).foregroundStyle(.secondary)
                            }
                        case .unreadable(let name, let reason):
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(name) · 기록 파일 손상/판독 불가").font(.caption.monospaced()).foregroundStyle(.red)
                                Text(reason).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("정리") {
                    Button("진단 파일 정리", role: .destructive) { model.cleanupDiagnosticFiles() }.buttonStyle(.borderless).disabled(model.isRunning)
                    Text(model.cleanupSummary).font(.caption.monospaced())
                }
                Section("로그") {
                    ForEach(Array(model.log.enumerated()), id: \.offset) { Text($0.element).font(.caption.monospaced()) }
                }
            }
            .navigationTitle("Phase 6 Media Spike")
            .photosPicker(isPresented: $showPicker, selection: $model.pickerItems, matching: .videos, preferredItemEncoding: Phase6MediaSpikeModel.pickerEncoding)
            .onChange(of: showPicker) { _, presented in if !presented { model.handlePickerSelection() } }
            .sheet(isPresented: $model.playbackPresented, onDismiss: { model.closePlayback() }) {
                Phase6SpikePlaybackSheet(controller: model.playback) { model.closePlayback() }
            }
        }
        .onAppear {
            MellowLog.app.info("Phase6MediaSpike: diagnostic surface presented")
            model.restoreExistingFiles()
        }
    }

    @ViewBuilder
    private func resultRows(_ r: Phase6SpikeResult) -> some View {
        let rows: [(String, String)] = [
            ("결과", "success=\(r.succeeded) cancelled=\(r.cancelled) reader=\(r.readerStatus) writer=\(r.writerStatus)"),
            ("오류", r.errorDescription ?? "none"),
            ("경과", String(format: "%.2f s (video %d / audio %d samples)", r.elapsed, r.videoSamples, r.audioSamples)),
            ("thermal before/peak/after", "\(Phase6SpikeMetrics.thermalName(r.thermalBefore)) / \(Phase6SpikeMetrics.thermalName(r.thermalPeak)) / \(Phase6SpikeMetrics.thermalName(r.thermalAfter))"),
            ("footprint before/peak/after", "\(Phase6SpikeFormat.bytes(r.footprintBefore)) / \(Phase6SpikeFormat.bytes(r.footprintPeak)) / \(Phase6SpikeFormat.bytes(r.footprintAfter))"),
            ("free before/min-during/after", "\(Phase6SpikeFormat.bytes(r.capacityBefore)) / \(Phase6SpikeFormat.bytes(r.capacityMinimumDuring)) / \(Phase6SpikeFormat.bytes(r.capacityAfter))"),
            ("peak temporary delta", Phase6SpikeFormat.bytes(r.peakTemporaryDelta)),
            ("source → output bytes", "\(Phase6SpikeFormat.bytes(r.sourceBytes)) → \(Phase6SpikeFormat.bytes(r.outputBytes))"),
            ("cancel: partial existed / cleanup ok / exists after", "\(r.partialOutputExistedAfterCancel.map(String.init) ?? "n/a") / \(r.cleanupSucceeded.map(String.init) ?? "n/a") / \(r.outputExistsAfterCleanup.map(String.init) ?? "n/a")"),
            ("cancel: source / progress / requests / auto threshold", "\(r.cancellationSource ?? "n/a") / \(r.cancellationRequestedProgress.map { String(format: "%.3f", $0) } ?? "n/a") / \(r.cancellationRequestCount.map(String.init) ?? "n/a") / \(r.autoCancelThreshold.map { String(format: "%.2f", $0) } ?? "off")"),
            ("source unchanged (bytes / mtime)", r.sourceUnchanged.map(String.init) ?? "n/a"),
            ("notes", r.notes.joined(separator: " | ")),
        ]
        ForEach(Array(rows.enumerated()), id: \.offset) { row in
            VStack(alignment: .leading, spacing: 2) { Text(row.element.0).font(.caption2).foregroundStyle(.secondary); Text(row.element.1).font(.caption.monospaced()) }
        }
    }
}

/// Dedicated playback surface (a sheet, not a List row) so the `VideoPlayer` layer and the single
/// `AVPlayer` owned by the controller are not recycled with table cells.
struct Phase6SpikePlaybackSheet: View {
    let controller: Phase6SpikePlaybackController
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(controller.target?.label ?? "-").font(.title2.bold())
                if let player = controller.player {
                    VideoPlayer(player: player).frame(maxWidth: .infinity).frame(height: 420).background(Color.black)
                } else {
                    Text(controller.loadError ?? "플레이어 없음").foregroundStyle(.red).frame(height: 120)
                }
                HStack(spacing: 16) {
                    Button("재생") { controller.play() }.buttonStyle(.borderedProminent)
                    Button("일시정지") { controller.pause() }.buttonStyle(.bordered)
                    Button("처음부터") { controller.restart() }.buttonStyle(.bordered)
                    Button("닫기", role: .cancel) { onClose() }.buttonStyle(.bordered)
                }
                .disabled(controller.player == nil && controller.loadError != nil)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(controller.diagnosticsRows.enumerated()), id: \.offset) { row in
                            VStack(alignment: .leading, spacing: 1) { Text(row.element.0).font(.caption2).foregroundStyle(.secondary); Text(row.element.1).font(.caption.monospaced()) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
            }
            .padding(.top)
            .navigationTitle("진단 재생")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(false)
    }
}
#endif
