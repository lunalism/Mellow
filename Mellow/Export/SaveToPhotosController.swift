import AVFoundation
import Foundation

// 클립 목록을 한 편으로 만들어 사진 앱에 넣는 동선 (1-18).
//
// 병합 → 익스포트 → 사진 앱 저장을 순서대로 하고 구간별 시간을 남긴다.
// 세 단계가 서로 다른 이유로 실패하므로, 어디서 멈췄는지 화면에 그대로 보여준다.
//
// Phase 1 확인용이다. 진행률·재시도·취소는 없다. 저장 화면은 3-13 에서 만든다.
@MainActor
final class SaveToPhotosController: ObservableObject {

    enum State: Equatable {
        case idle
        case askingPermission
        case merging
        case exporting
        case saving
        case saved(SaveTimings)
        case reencoding
        case reencoded(ReencodeMeasurement)
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .askingPermission, .merging, .exporting, .saving, .reencoding: return true
            case .idle, .saved, .reencoded, .failed: return false
            }
        }

        var label: String {
            switch self {
            case .idle: return "대기"
            case .askingPermission: return "권한 확인 중"
            case .merging: return "합치는 중"
            case .exporting: return "내보내는 중"
            case .saving: return "사진 앱에 저장 중"
            case .saved: return "완료"
            case .reencoding: return "재인코딩 중"
            case .reencoded: return "재인코딩 완료"
            case .failed: return "실패"
            }
        }
    }

    @Published private(set) var state: State = .idle
    /// 직전 저장의 구간별 시간. 실패해도 거기까지 잰 값은 남긴다.
    @Published private(set) var timings = SaveTimings()
    /// 직전 단일 클립 재인코딩 측정값 (1-19).
    @Published private(set) var reencode = ReencodeMeasurement()
    /// 이번 실행에서 돌린 저장 라운드들의 요약. 회차별로 느려지는지 본다.
    @Published private(set) var roundHistory: [String] = []
    /// 사진 앱 권한 상태. 거부 안내를 띄우는 근거.
    @Published private(set) var permission: PermissionState = .undetermined

    /// 파일을 옮길지 복사할지. 1-19 실측에서 성능 차이가 없어 **복사로 확정**했다.
    /// 스위치는 1-21 등에서 다시 대조할 일이 있어 남겨둔다.
    @Published var moveFile = false

    init() {
        permission = PhotoLibrarySaver.currentPermission()
    }

    func refreshPermission() {
        permission = PhotoLibrarySaver.currentPermission()
    }

    /// 클립들을 한 편으로 만들어 사진 앱에 넣는다.
    func save(clips urls: [URL]) async {
        guard !state.isBusy else { return }
        guard !urls.isEmpty else {
            state = .failed("저장할 클립이 없습니다.")
            return
        }

        var measured = SaveTimings()
        measured.clipCount = urls.count
        timings = measured

        // 0) 권한 — 병합·익스포트보다 먼저 해결한다.
        //
        // 두 가지 이유가 있고 둘 다 실측에서 나왔다.
        //   (1) 미결정 상태의 첫 저장은 시스템 팝업을 띄우고 사용자가 누를 때까지
        //       기다린다. 실측 22.7초. 이걸 저장 구간 안에 두면 1-19 의 숫자가
        //       사람 반응 속도로 오염된다. 그래서 따로 잰다
        //   (2) 거부 상태라면 병합·익스포트가 통째로 헛일이다. 클립 30개면
        //       800ms 를 버리고 임시 파일까지 만들었다 지우게 된다
        state = .askingPermission
        let startedPermission = CFAbsoluteTimeGetCurrent()
        let granted = await PhotoLibrarySaver.requestPermission()
        measured.permissionWait = CFAbsoluteTimeGetCurrent() - startedPermission
        permission = granted
        timings = measured

        // 총 시간은 권한이 정해진 뒤부터 잰다. 앞의 대기는 따로 들고 있다.
        let startedAll = CFAbsoluteTimeGetCurrent()

        guard granted.isAuthorized else {
            finish(.failed(PhotoLibrarySaveError.permissionDenied(granted).description),
                   measured, startedAll)
            return
        }

        // 1) 병합 — 파일을 쓰지 않는다. 편집 목록을 만드는 것뿐이다.
        state = .merging
        let startedMerge = CFAbsoluteTimeGetCurrent()
        let merge = await ClipMerger.merge(urls)
        measured.merge = CFAbsoluteTimeGetCurrent() - startedMerge
        measured.compositionSeconds = CMTimeGetSeconds(merge.compositionDuration)
        timings = measured

        if let fatal = merge.fatal {
            finish(.failed("병합 실패 — \(fatal)"), measured, startedAll)
            return
        }
        // AVMutableComposition 은 가변 객체다. 익스포트 중에 바뀌지 않도록 스냅샷을 뜬다.
        guard let asset = merge.composition.copy() as? AVComposition else {
            finish(.failed("컴포지션 스냅샷을 만들지 못했습니다."), measured, startedAll)
            return
        }

        // 2) 익스포트 — passthrough. 재인코딩이 일어나면 여기서 시간이 튄다.
        state = .exporting
        let round = Self.makeRoundDirectory()
        defer { Self.discardRoundDirectory(round) }

        let output = round.appendingPathComponent("session.mov")
        let outcome: ExportOutcome
        do {
            let startedExport = CFAbsoluteTimeGetCurrent()
            outcome = try await ClipExporter.export(asset,
                                                    preset: ClipExporter.passthroughPreset,
                                                    to: output,
                                                    as: .mov)
            measured.export = CFAbsoluteTimeGetCurrent() - startedExport
            measured.exportedBytes = outcome.fileSize ?? 0
            timings = measured
        } catch {
            // 실패해도 반쯤 쓰인 파일이 남을 수 있다.
            PhotoLibrarySaver.discardTemporaryFile(at: output)
            finish(.failed("익스포트 실패 — \(error)"), measured, startedAll)
            return
        }

        // 3) 사진 앱 저장 — 여기부터는 우리 프로세스 밖이다.
        //    save 가 임시 파일 소유권을 가져가므로 성공/실패와 무관하게 파일은 사라진다.
        state = .saving
        do {
            let startedSave = CFAbsoluteTimeGetCurrent()
            let saved = try await PhotoLibrarySaver.save(temporaryVideoAt: outcome.outputURL,
                                                         moveFile: moveFile)
            measured.photoLibrary = CFAbsoluteTimeGetCurrent() - startedSave
            measured.movedFile = saved.movedFile
            permission = PhotoLibrarySaver.currentPermission()
            finish(.saved(measured), measured, startedAll)
        } catch {
            permission = PhotoLibrarySaver.currentPermission()
            let message = (error as? PhotoLibrarySaveError)?.description ?? "\(error)"
            finish(.failed(message), measured, startedAll)
        }
    }

    // MARK: - 마무리

    private func finish(_ result: State, _ measured: SaveTimings, _ startedAll: CFAbsoluteTime) {
        var final = measured
        final.total = CFAbsoluteTimeGetCurrent() - startedAll
        timings = final
        final.log()

        // 회차별 추이는 화면에서도 보여야 한다. 로그를 못 볼 때가 있다.
        if case .saved = result {
            roundHistory.append("\(roundHistory.count + 1)) "
                                + (final.movedFile ? "이동 " : "복사 ") + final.compact)
        }

        // .saved 는 시간을 함께 들고 있어야 화면에서 바로 쓴다.
        if case .saved = result {
            state = .saved(final)
        } else {
            state = result
        }
    }

    // MARK: - 라운드 단위 출력 경로

    // 라운드마다 디렉터리를 새로 잡고 끝나면 통째로 지운다.
    //
    // Mac 에서 같은 출력 디렉터리에 큰 파일을 쌓으며 반복했더니 30클립
    // 익스포트가 817ms → 2194ms 로 밀렸다(1-17). 원인을 특정하지는 못했고
    // 디스크 쓰기 속도나 발열은 그대로였다. 실기기에서도 나올 수 있으므로
    // 경로를 매번 새로 잡아 그 변수를 먼저 제거한다.
    private static func makeRoundDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mellow-export-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// shouldMoveFile 로 파일이 빠져나가면 빈 디렉터리가 남는다. 그것까지 지운다.
    private static func discardRoundDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - 단일 클립 재인코딩 (1-19 준비)

    /// 클립 하나를 `AVAssetExportPreset1920x1080` 으로 다시 굽고 시간을 잰다.
    ///
    /// 세션 방향 모델 선택지 (c) "촬영 직후 단일 클립 정규화"의 실현 가능성이
    /// 이 값에 걸려 있다. 사진 앱에 넣지 않는다 — 재인코딩 비용만 보는 것이라
    /// 저장 구간이 섞이면 안 된다.
    func reencodeLastClip(_ urls: [URL]) async {
        guard !state.isBusy else { return }
        guard let url = urls.last else {
            state = .failed("재인코딩할 클립이 없습니다.")
            return
        }

        state = .reencoding

        let round = Self.makeRoundDirectory()
        defer { Self.discardRoundDirectory(round) }
        let output = round.appendingPathComponent("reencoded.mov")

        var measurement = ReencodeMeasurement()
        let asset = AVURLAsset(url: url)
        measurement.clipSeconds = CMTimeGetSeconds((try? await asset.load(.duration)) ?? .zero)

        do {
            let started = CFAbsoluteTimeGetCurrent()
            let outcome = try await ClipExporter.export(asset,
                                                        preset: AVAssetExportPreset1920x1080,
                                                        to: output,
                                                        as: .mov)
            measurement.elapsed = CFAbsoluteTimeGetCurrent() - started
            measurement.outputBytes = outcome.fileSize ?? 0
        } catch {
            state = .failed("재인코딩 실패 — \(error)")
            return
        }

        reencode = measurement
        measurement.log()
        state = .reencoded(measurement)
    }
}
