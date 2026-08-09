import AVFoundation
import CoreMedia
import Foundation

/// 영상 파일 하나에서 뽑아낸 스펙 스냅샷.
///
/// 목적은 하나다 — 여러 클립이 **재인코딩 없이 붙일 수 있을 만큼 동일한가**를
/// 눈으로 확인하는 것. 판정 자체는 `ClipSpec.compare(_:)` 가 한다.
struct ClipSpec {

    struct Video {
        var naturalSize: CGSize
        var dimensions: CMVideoDimensions
        /// fourcc 를 사람이 읽는 문자열로. 예: "avc1", "hvc1"
        var mediaSubType: String
        var nominalFrameRate: Float
        var minFrameDuration: CMTime
        var preferredTransform: CGAffineTransform
        var estimatedDataRate: Float

        var colorPrimaries: String?
        var transferFunction: String?
        var yCbCrMatrix: String?
    }

    struct Audio {
        /// fourcc 문자열. 예: "aac ", "lpcm"
        var formatID: String
        var sampleRate: Double
        var channelCount: UInt32
    }

    var url: URL
    /// 출력에서 클립을 식별할 이름. 기본값은 파일명.
    var name: String
    var duration: Double
    var fileSize: Int64?

    /// 트랙이 아예 없을 수 있다. 없음을 없음으로 들고 있어야
    /// "값이 다르다"와 "트랙이 없다"를 비교 단계에서 구분할 수 있다.
    var video: Video?
    var audio: Audio?
}

// MARK: - 추출

extension ClipSpec {

    /// iOS 16+ 의 async `load(_:)` 계열만 사용한다.
    /// `asset.tracks`, `asset.duration`, `track.preferredTransform` 같은
    /// 동기 프로퍼티는 deprecated 이므로 쓰지 않는다.
    static func load(from url: URL) async throws -> ClipSpec {
        let asset = AVURLAsset(url: url)

        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        var video: Video?
        if let track = videoTracks.first {
            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let frameRate = try await track.load(.nominalFrameRate)
            let minFrameDuration = try await track.load(.minFrameDuration)
            let dataRate = try await track.load(.estimatedDataRate)
            let formats = try await track.load(.formatDescriptions)

            var dimensions = CMVideoDimensions(width: 0, height: 0)
            var subType = "-"
            var primaries: String?
            var transfer: String?
            var matrix: String?

            if let format = formats.first {
                dimensions = CMVideoFormatDescriptionGetDimensions(format)
                subType = fourCC(format.mediaSubType.rawValue)
                primaries = stringExtension(format, kCMFormatDescriptionExtension_ColorPrimaries)
                transfer = stringExtension(format, kCMFormatDescriptionExtension_TransferFunction)
                matrix = stringExtension(format, kCMFormatDescriptionExtension_YCbCrMatrix)
            }

            video = Video(
                naturalSize: naturalSize,
                dimensions: dimensions,
                mediaSubType: subType,
                nominalFrameRate: frameRate,
                minFrameDuration: minFrameDuration,
                preferredTransform: transform,
                estimatedDataRate: dataRate,
                colorPrimaries: primaries,
                transferFunction: transfer,
                yCbCrMatrix: matrix
            )
        }

        var audio: Audio?
        if let track = audioTracks.first {
            let formats = try await track.load(.formatDescriptions)
            if let format = formats.first,
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                audio = Audio(
                    formatID: fourCC(asbd.mFormatID),
                    sampleRate: asbd.mSampleRate,
                    channelCount: asbd.mChannelsPerFrame
                )
            }
        }

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))
            .flatMap(\.fileSize)
            .map(Int64.init)

        return ClipSpec(
            url: url,
            name: url.lastPathComponent,
            duration: duration.seconds,
            fileSize: fileSize,
            video: video,
            audio: audio
        )
    }

    private static func stringExtension(_ format: CMFormatDescription, _ key: CFString) -> String? {
        CMFormatDescriptionGetExtension(format, extensionKey: key) as? String
    }

    /// FourCharCode → "avc1". 인쇄 불가 바이트는 \xNN 으로 이스케이프한다.
    private static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [
            UInt8(truncatingIfNeeded: code >> 24),
            UInt8(truncatingIfNeeded: code >> 16),
            UInt8(truncatingIfNeeded: code >> 8),
            UInt8(truncatingIfNeeded: code)
        ]
        return bytes.map { byte in
            (0x20...0x7E).contains(byte)
                ? String(UnicodeScalar(byte))
                : String(format: "\\x%02X", byte)
        }.joined()
    }
}

// MARK: - 필드 정의
//
// description 과 compare 가 같은 목록을 공유한다.
// 필드를 추가할 때 두 군데를 고치지 않도록 여기 한 곳에만 적는다.

extension ClipSpec {

    fileprivate enum TrackKind {
        case video, audio

        var label: String {
            switch self {
            case .video: return "비디오 트랙"
            case .audio: return "오디오 트랙"
            }
        }

        var groupTitle: String {
            switch self {
            case .video: return "[비디오]"
            case .audio: return "[오디오]"
            }
        }
    }

    fileprivate func hasTrack(_ kind: TrackKind) -> Bool {
        switch kind {
        case .video: return video != nil
        case .audio: return audio != nil
        }
    }

    fileprivate struct Field {
        let label: String
        /// 값 추출. 해당 트랙이 있는 클립에 대해서만 호출된다.
        let value: (ClipSpec) -> String
    }

    /// 재인코딩 없는 병합(passthrough)을 하려면 클립 전체에서 같아야 하는 값들.
    /// 비디오와 오디오를 같은 비중으로 다룬다 — 오디오 스펙은 사용자가
    /// 이어폰을 끼고 빼는 것만으로 세션 중간에 갈릴 수 있어서
    /// 우리 시나리오에서 가장 현실적인 불일치 원인이다.
    fileprivate static func matchRequired(for kind: TrackKind) -> [Field] {
        switch kind {
        case .video:
            return [
                Field(label: "코덱") { $0.video!.mediaSubType },
                Field(label: "해상도 (encoded)") {
                    let d = $0.video!.dimensions
                    return "\(d.width)×\(d.height)"
                },
                Field(label: "해상도 (natural)") {
                    let s = $0.video!.naturalSize
                    return "\(num(s.width))×\(num(s.height))"
                },
                Field(label: "프레임레이트") {
                    String(format: "%.3f fps", $0.video!.nominalFrameRate)
                },
                Field(label: "minFrameDuration") {
                    frameDuration($0.video!.minFrameDuration)
                },
                Field(label: "preferredTransform") {
                    transformText($0.video!.preferredTransform)
                },
                Field(label: "colorPrimaries") { $0.video!.colorPrimaries ?? "(미지정)" },
                Field(label: "transferFunction") { $0.video!.transferFunction ?? "(미지정)" },
                Field(label: "YCbCrMatrix") { $0.video!.yCbCrMatrix ?? "(미지정)" }
            ]
        case .audio:
            return [
                Field(label: "코덱") { $0.audio!.formatID },
                Field(label: "샘플레이트") {
                    String(format: "%.0f Hz", $0.audio!.sampleRate)
                },
                Field(label: "채널 수") { "\($0.audio!.channelCount)ch" }
            ]
        }
    }

    /// 클립마다 달라도 정상인 값들. 판정에 넣지 않는다.
    fileprivate static let informational: [Field] = [
        Field(label: "길이") { String(format: "%.3f s", $0.duration) },
        Field(label: "파일 크기") { $0.fileSize.map(byteText) ?? "(알 수 없음)" },
        Field(label: "비트레이트") {
            guard let v = $0.video else { return "-" }
            return String(format: "%.2f Mbps", v.estimatedDataRate / 1_000_000)
        }
    ]

    fileprivate static var allLabels: [String] {
        matchRequired(for: .video).map(\.label)
            + matchRequired(for: .audio).map(\.label)
            + informational.map(\.label)
            + [TrackKind.video.label, TrackKind.audio.label]
    }
}

// MARK: - 한 클립 출력

extension ClipSpec: CustomStringConvertible {

    var description: String {
        let width = ClipSpec.allLabels.map(displayWidth).max() ?? 0
        var lines = ["── \(name) ──"]

        for kind in [ClipSpec.TrackKind.video, .audio] {
            lines.append(" \(kind.groupTitle)")
            guard hasTrack(kind) else {
                lines.append("  · \(pad(kind.label, to: width))  (없음)")
                continue
            }
            for field in ClipSpec.matchRequired(for: kind) {
                lines.append("  · \(pad(field.label, to: width))  \(field.value(self))")
            }
        }

        lines.append(" [참고]")
        for field in ClipSpec.informational {
            lines.append("  · \(pad(field.label, to: width))  \(field.value(self))")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 여러 클립 비교 (이 유틸의 본체)

extension ClipSpec {

    /// 필드별로 전 클립의 값이 같은지 판정한다.
    /// 같으면 값 하나만, 다르면 클립별 값을 전부 나열한다.
    ///
    /// "값이 다르다"와 "트랙이 아예 없다"는 원인이 달라서 따로 센다.
    /// 트랙이 **전부** 없으면 그건 일치로 본다 — 무음 클립끼리는 붙는다.
    static func compare(_ specs: [ClipSpec]) -> String {
        guard !specs.isEmpty else { return "비교할 클립이 없다." }
        guard specs.count > 1 else { return specs[0].description }

        let width = allLabels.map(displayWidth).max() ?? 0

        var lines: [String] = []
        lines.append("━━━ 클립 스펙 비교 · \(specs.count)개 ━━━")
        for (index, spec) in specs.enumerated() {
            lines.append("  [\(index + 1)] \(spec.name)")
        }

        var valueMismatches: [String] = []
        var trackGaps: [String] = []

        lines.append("")
        lines.append("● 병합 조건 — passthrough 하려면 전부 같아야 한다")

        for kind in [TrackKind.video, .audio] {
            lines.append("")
            lines.append(" \(kind.groupTitle)")

            let present = specs.filter { $0.hasTrack(kind) }

            if present.isEmpty {
                // 전부 없음 = 일치. 붙이는 데 문제 없다.
                lines.append("  ✓ \(pad(kind.label, to: width))  전 클립에 없음 (일치)")
                continue
            }

            if present.count == specs.count {
                lines.append("  ✓ \(pad(kind.label, to: width))  전 클립에 있음")
            } else {
                // 값 불일치가 아니라 구성 자체가 다른 경우다. 따로 표시한다.
                trackGaps.append(kind.label)
                lines.append("  ⚠ \(pad(kind.label, to: width))  ← 트랙 없는 클립이 섞여 있다")
                for (index, spec) in specs.enumerated() {
                    let mark = spec.hasTrack(kind) ? "있음" : "없음  ←"
                    lines.append("      \(pad("[\(index + 1)]", to: 5)) \(mark)")
                }
            }

            // 세부 필드는 트랙이 있는 클립끼리만 비교한다.
            // 없는 클립을 "값이 다르다"로 또 세면 원인이 두 번 계상된다.
            let scopeNote = present.count == specs.count
                ? ""
                : "   (트랙 있는 \(present.count)개 기준)"

            for field in matchRequired(for: kind) {
                let values = present.map(field.value)
                if Set(values).count == 1 {
                    lines.append("  ✓ \(pad(field.label, to: width))  \(values[0])\(scopeNote)")
                } else {
                    valueMismatches.append("\(kind.groupTitle) \(field.label)")
                    lines.append("  ✗ \(pad(field.label, to: width))  ← 불일치\(scopeNote)")
                    for (index, spec) in specs.enumerated() {
                        let text = spec.hasTrack(kind) ? field.value(spec) : "— (트랙 없음)"
                        lines.append("      \(pad("[\(index + 1)]", to: 5)) \(text)")
                    }
                }
            }
        }

        lines.append("")
        lines.append(" [참고] — 클립마다 달라도 정상")
        for field in informational {
            let values = specs.map(field.value)
            if Set(values).count == 1 {
                lines.append("  · \(pad(field.label, to: width))  \(values[0])")
            } else {
                let joined = values.enumerated()
                    .map { "[\($0.offset + 1)] \($0.element)" }
                    .joined(separator: "   ")
                lines.append("  · \(pad(field.label, to: width))  \(joined)")
            }
        }

        lines.append("")
        if valueMismatches.isEmpty && trackGaps.isEmpty {
            lines.append("━━━ 판정: 전 필드 일치 — 재인코딩 없이 병합 가능 ━━━")
        } else {
            lines.append("━━━ 판정: passthrough 병합 불가 ━━━")
            if !trackGaps.isEmpty {
                lines.append("    트랙 누락 \(trackGaps.count)종: "
                             + trackGaps.joined(separator: ", ")
                             + " — 일부 클립에만 존재")
            }
            if !valueMismatches.isEmpty {
                lines.append("    값 불일치 \(valueMismatches.count)개: "
                             + valueMismatches.joined(separator: ", "))
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 포맷 헬퍼

/// 소수부가 없으면 정수로. 1080.0 → "1080"
private func num(_ value: CGFloat) -> String {
    value == value.rounded()
        ? String(format: "%.0f", value)
        : String(format: "%.3f", value)
}

private func frameDuration(_ time: CMTime) -> String {
    guard time.isValid, time.isNumeric, time.seconds > 0 else { return "(무효)" }
    return String(format: "%d/%d  (%.3f fps)",
                  time.value, time.timescale, 1 / time.seconds)
}

/// 여섯 값 그대로 + 회전각. 1-11(회전 정보 일치 확인)에서 각도가 바로 필요하다.
private func transformText(_ t: CGAffineTransform) -> String {
    let values = [t.a, t.b, t.c, t.d, t.tx, t.ty].map(num).joined(separator: " ")
    let degrees = atan2(Double(t.b), Double(t.a)) * 180 / .pi
    let normalized = (degrees.rounded() + 360).truncatingRemainder(dividingBy: 360)
    return "[\(values)]  \(num(CGFloat(normalized)))°"
}

private func byteText(_ bytes: Int64) -> String {
    String(format: "%.2f MB (%lld B)", Double(bytes) / 1_048_576, bytes)
}

/// 한글은 콘솔에서 2칸을 먹는다. 문자 수로 패딩하면 열이 어긋난다.
private func displayWidth(_ text: String) -> Int {
    text.unicodeScalars.reduce(0) { total, scalar in
        total + (isWide(scalar) ? 2 : 1)
    }
}

private func isWide(_ scalar: UnicodeScalar) -> Bool {
    switch scalar.value {
    case 0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3,
         0xF900...0xFAFF, 0xFE30...0xFE6F, 0xFF00...0xFF60, 0xFFE0...0xFFE6:
        return true
    default:
        return false
    }
}

private func pad(_ text: String, to width: Int) -> String {
    text + String(repeating: " ", count: max(0, width - displayWidth(text)))
}
