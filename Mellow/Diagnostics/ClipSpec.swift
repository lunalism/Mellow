import AVFoundation
import CoreMedia
import Foundation

/// 트랙 하나의 상태. "없음"과 "읽지 못함"을 구분하는 것이 핵심이다.
///
/// 둘을 섞으면 메타데이터 추출에 실패한 클립들이 서로 "일치"로 판정돼
/// 진단 불능 입력이 성공으로 승격된다.
enum TrackStatus<Spec> {
    case absent
    case present(Spec)
    case unreadable(reason: String)

    var spec: Spec? {
        if case .present(let spec) = self { return spec }
        return nil
    }

    var isAbsent: Bool {
        if case .absent = self { return true }
        return false
    }

    var isUnreadable: Bool {
        if case .unreadable = self { return true }
        return false
    }

    var stateText: String {
        switch self {
        case .absent: return "없음"
        case .present: return "있음"
        case .unreadable(let reason): return "읽기 실패 — \(reason)"
        }
    }
}

/// 영상 파일 하나에서 뽑아낸 스펙 스냅샷.
///
/// 목적은 **여러 클립의 스펙이 서로 다른지**를 눈으로 확인하는 것이다.
/// 병합이 실제로 성립하는지는 `AVMutableComposition` 으로 붙여보고
/// passthrough 익스포트를 돌려봐야 안다 (Tasks 1-12 ~ 1-17).
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

    var video: TrackStatus<Video>
    var audio: TrackStatus<Audio>
}

// MARK: - 추출

extension ClipSpec {

    /// iOS 16+ 의 async `load(_:)` 계열만 사용한다.
    /// `asset.tracks`, `asset.duration`, `track.preferredTransform` 같은
    /// 동기 프로퍼티는 deprecated 이므로 쓰지 않는다.
    ///
    /// 트랙은 있는데 포맷 정보를 못 읽으면 기본값으로 채우지 않고
    /// `.unreadable` 로 남긴다. 0×0 같은 sentinel 을 넣으면 추출 실패끼리
    /// 값이 같아져서 "일치"로 판정돼버린다.
    static func load(from url: URL) async throws -> ClipSpec {
        let asset = AVURLAsset(url: url)

        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        var video: TrackStatus<Video> = .absent
        if let track = videoTracks.first {
            let naturalSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let frameRate = try await track.load(.nominalFrameRate)
            let minFrameDuration = try await track.load(.minFrameDuration)
            let dataRate = try await track.load(.estimatedDataRate)
            let formats = try await track.load(.formatDescriptions)

            if let format = formats.first {
                video = .present(Video(
                    naturalSize: naturalSize,
                    dimensions: CMVideoFormatDescriptionGetDimensions(format),
                    mediaSubType: fourCCText(format.mediaSubType.rawValue),
                    nominalFrameRate: frameRate,
                    minFrameDuration: minFrameDuration,
                    preferredTransform: transform,
                    estimatedDataRate: dataRate,
                    colorPrimaries: stringExtension(format, kCMFormatDescriptionExtension_ColorPrimaries),
                    transferFunction: stringExtension(format, kCMFormatDescriptionExtension_TransferFunction),
                    yCbCrMatrix: stringExtension(format, kCMFormatDescriptionExtension_YCbCrMatrix)
                ))
            } else {
                video = .unreadable(reason: "formatDescription 없음")
            }
        }

        var audio: TrackStatus<Audio> = .absent
        if let track = audioTracks.first {
            let formats = try await track.load(.formatDescriptions)
            if let format = formats.first {
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                    audio = .present(Audio(
                        formatID: fourCCText(asbd.mFormatID),
                        sampleRate: asbd.mSampleRate,
                        channelCount: asbd.mChannelsPerFrame
                    ))
                } else {
                    audio = .unreadable(reason: "AudioStreamBasicDescription 없음")
                }
            } else {
                audio = .unreadable(reason: "formatDescription 없음")
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
    ///
    /// 소스 설정(activeFormat)을 찍는 쪽에서도 같은 표기가 필요해서 열어둔다.
    /// UI 의존이 없으므로 macOS 단독 컴파일 제약은 그대로다.
    static func fourCCText(_ code: FourCharCode) -> String {
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
// 판정용 key 와 표시용 display 를 분리한다.
// CMTime 처럼 표기가 달라도 값이 같을 수 있는 필드가 있어서,
// 표시 문자열을 그대로 비교하면 잘못된 불일치가 난다.

extension ClipSpec {

    fileprivate struct Field<Spec> {
        let label: String
        let key: (Spec) -> String
        let display: (Spec) -> String

        init(_ label: String, _ both: @escaping (Spec) -> String) {
            self.label = label
            self.key = both
            self.display = both
        }

        init(_ label: String, key: @escaping (Spec) -> String, display: @escaping (Spec) -> String) {
            self.label = label
            self.key = key
            self.display = display
        }
    }

    /// 재인코딩 없는 병합을 노린다면 클립 전체에서 같아야 하는 값들.
    /// 비디오와 오디오를 같은 비중으로 다룬다 — 오디오 스펙은 사용자가
    /// 이어폰을 끼고 빼는 것만으로 세션 중간에 갈릴 수 있어서
    /// 우리 시나리오에서 가장 현실적인 불일치 원인이다.
    fileprivate static let videoFields: [Field<Video>] = [
        Field("코덱") { $0.mediaSubType },
        Field("해상도 (encoded)") { "\($0.dimensions.width)×\($0.dimensions.height)" },
        Field("해상도 (natural)") { "\(num($0.naturalSize.width))×\(num($0.naturalSize.height))" },
        Field("프레임레이트") { String(format: "%.3f fps", $0.nominalFrameRate) },
        Field("minFrameDuration",
              key: { frameDurationKey($0.minFrameDuration) },
              display: { frameDurationText($0.minFrameDuration) }),
        Field("preferredTransform") { transformText($0.preferredTransform) },
        Field("colorPrimaries") { $0.colorPrimaries ?? "(미지정)" },
        Field("transferFunction") { $0.transferFunction ?? "(미지정)" },
        Field("YCbCrMatrix") { $0.yCbCrMatrix ?? "(미지정)" }
    ]

    fileprivate static let audioFields: [Field<Audio>] = [
        Field("코덱") { $0.formatID },
        Field("샘플레이트") { String(format: "%.0f Hz", $0.sampleRate) },
        Field("채널 수") { "\($0.channelCount)ch" }
    ]

    /// 클립마다 달라도 정상인 값들. 판정에 넣지 않는다.
    fileprivate static let informational: [Field<ClipSpec>] = [
        Field("길이") { String(format: "%.3f s", $0.duration) },
        Field("파일 크기") { $0.fileSize.map(byteText) ?? "(알 수 없음)" },
        Field("비트레이트") {
            guard let video = $0.video.spec else { return "-" }
            return String(format: "%.2f Mbps", video.estimatedDataRate / 1_000_000)
        }
    ]

    fileprivate static let videoLabel = "비디오 트랙"
    fileprivate static let audioLabel = "오디오 트랙"

    fileprivate static var labelWidth: Int {
        let labels = videoFields.map(\.label)
            + audioFields.map(\.label)
            + informational.map(\.label)
            + [videoLabel, audioLabel]
        return labels.map(displayWidth).max() ?? 0
    }
}

// MARK: - 한 클립 출력

extension ClipSpec: CustomStringConvertible {

    var description: String {
        let width = ClipSpec.labelWidth
        var lines = ["── \(name) ──"]

        lines.append(" [비디오]")
        lines += Self.describe(status: video, label: ClipSpec.videoLabel,
                               fields: ClipSpec.videoFields, width: width)

        lines.append(" [오디오]")
        lines += Self.describe(status: audio, label: ClipSpec.audioLabel,
                               fields: ClipSpec.audioFields, width: width)

        lines.append(" [참고]")
        for field in ClipSpec.informational {
            lines.append("  · \(pad(field.label, to: width))  \(field.display(self))")
        }
        return lines.joined(separator: "\n")
    }

    private static func describe<Spec>(
        status: TrackStatus<Spec>,
        label: String,
        fields: [Field<Spec>],
        width: Int
    ) -> [String] {
        guard let spec = status.spec else {
            return ["  · \(pad(label, to: width))  (\(status.stateText))"]
        }
        return fields.map { field in
            "  · \(pad(field.label, to: width))  \(field.display(spec))"
        }
    }
}

// MARK: - 여러 클립 비교 (이 유틸의 본체)

extension ClipSpec {

    /// 필드별로 전 클립의 값이 같은지 대조한다.
    /// 같으면 값 하나만, 다르면 클립별 값을 전부 나열한다.
    ///
    /// 세 가지를 따로 센다.
    /// - 값 불일치: 트랙이 있고 읽었는데 값이 다르다
    /// - 트랙 누락: 어떤 클립엔 있고 어떤 클립엔 없다
    /// - 읽기 실패: 트랙은 있는데 포맷 정보를 못 읽었다 → **판정 자체를 보류한다**
    ///
    /// 트랙이 전 클립에 **없는** 것은 일치로 본다. 무음 클립끼리는 붙는다.
    /// 하지만 **못 읽은** 것에는 이 규칙을 적용하지 않는다.
    static func compare(_ specs: [ClipSpec]) -> String {
        guard !specs.isEmpty else { return "비교할 클립이 없다." }
        guard specs.count > 1 else { return specs[0].description }

        let width = labelWidth
        var lines: [String] = []
        lines.append("━━━ 클립 스펙 비교 · \(specs.count)개 ━━━")
        for (index, spec) in specs.enumerated() {
            lines.append("  [\(index + 1)] \(spec.name)")
        }

        var valueMismatches: [String] = []
        var trackGaps: [String] = []
        var readFailures: [String] = []

        lines.append("")
        lines.append("● 스펙 대조 — 재인코딩 없이 붙이려면 전부 같아야 하는 값들")

        lines.append("")
        lines.append(" [비디오]")
        compareGroup(
            label: videoLabel, groupTitle: "[비디오]",
            statuses: specs.map(\.video), fields: videoFields, width: width,
            lines: &lines, valueMismatches: &valueMismatches,
            trackGaps: &trackGaps, readFailures: &readFailures
        )

        lines.append("")
        lines.append(" [오디오]")
        compareGroup(
            label: audioLabel, groupTitle: "[오디오]",
            statuses: specs.map(\.audio), fields: audioFields, width: width,
            lines: &lines, valueMismatches: &valueMismatches,
            trackGaps: &trackGaps, readFailures: &readFailures
        )

        lines.append("")
        lines.append(" [참고] — 클립마다 달라도 정상")
        for field in informational {
            let values = specs.map(field.display)
            if Set(specs.map(field.key)).count == 1 {
                lines.append("  · \(pad(field.label, to: width))  \(values[0])")
            } else {
                let joined = values.enumerated()
                    .map { "[\($0.offset + 1)] \($0.element)" }
                    .joined(separator: "   ")
                lines.append("  · \(pad(field.label, to: width))  \(joined)")
            }
        }

        lines.append("")
        lines += verdict(valueMismatches: valueMismatches,
                         trackGaps: trackGaps,
                         readFailures: readFailures)
        return lines.joined(separator: "\n")
    }

    private static func compareGroup<Spec>(
        label: String,
        groupTitle: String,
        statuses: [TrackStatus<Spec>],
        fields: [Field<Spec>],
        width: Int,
        lines: inout [String],
        valueMismatches: inout [String],
        trackGaps: inout [String],
        readFailures: inout [String]
    ) {
        let present = statuses.compactMap(\.spec)
        let unreadableCount = statuses.filter(\.isUnreadable).count
        let absentCount = statuses.filter(\.isAbsent).count

        func listStates() {
            for (index, status) in statuses.enumerated() {
                let mark = status.spec == nil ? "  ←" : ""
                lines.append("      \(pad("[\(index + 1)]", to: 5)) \(status.stateText)\(mark)")
            }
        }

        if unreadableCount > 0 {
            // 못 읽은 트랙이 하나라도 있으면 이 그룹의 대조는 근거가 없다.
            readFailures.append(label)
            lines.append("  ⛔ \(pad(label, to: width))  ← 읽지 못한 트랙이 있다")
            listStates()
        } else if present.count == statuses.count {
            lines.append("  ✓ \(pad(label, to: width))  전 클립에 있음")
        } else if absentCount == statuses.count {
            lines.append("  ✓ \(pad(label, to: width))  전 클립에 없음 (일치)")
            return  // 비교할 값이 없다
        } else {
            trackGaps.append(label)
            lines.append("  ⚠ \(pad(label, to: width))  ← 트랙 없는 클립이 섞여 있다")
            listStates()
        }

        guard !present.isEmpty else { return }

        // 세부 필드는 읽어낸 클립끼리만 대조한다.
        let scopeNote = present.count == statuses.count
            ? ""
            : "   (읽어낸 \(present.count)개 기준)"

        for field in fields {
            let keys = present.map(field.key)
            if Set(keys).count == 1 {
                var line = "  ✓ \(pad(field.label, to: width))  \(field.display(present[0]))\(scopeNote)"
                // 값은 같은데 표기만 다른 경우(예: 1/30 과 2/60)를 숨기지 않는다.
                let displays = present.map(field.display)
                if Set(displays).count > 1 {
                    line += "   ※ 표기 차이: " + displays.enumerated()
                        .map { "[\($0.offset + 1)] \($0.element)" }
                        .joined(separator: ", ")
                }
                lines.append(line)
            } else {
                valueMismatches.append("\(groupTitle) \(field.label)")
                lines.append("  ✗ \(pad(field.label, to: width))  ← 불일치\(scopeNote)")
                for (index, status) in statuses.enumerated() {
                    let text = status.spec.map(field.display) ?? "— (\(status.stateText))"
                    lines.append("      \(pad("[\(index + 1)]", to: 5)) \(text)")
                }
            }
        }
    }

    /// 이 유틸이 확인할 수 있는 것은 "스펙 차이가 있느냐"까지다.
    /// 실제로 붙는지는 composition 과 passthrough 익스포트를 돌려봐야 안다.
    private static func verdict(
        valueMismatches: [String],
        trackGaps: [String],
        readFailures: [String]
    ) -> [String] {
        if !readFailures.isEmpty {
            return [
                "━━━ 판정 보류: 읽지 못한 트랙이 있어 대조가 성립하지 않는다 ━━━",
                "    읽기 실패 \(readFailures.count)종: \(readFailures.joined(separator: ", "))",
                "    이 상태에서는 스펙이 같은지 판단할 근거가 없다."
            ]
        }

        if valueMismatches.isEmpty && trackGaps.isEmpty {
            return [
                "━━━ 스펙 불일치 없음 — 대조한 모든 필드가 같다 ━━━",
                "    실제로 붙는지는 composition + passthrough 익스포트로 확인한다 (1-12 ~ 1-17)."
            ]
        }

        var lines = ["━━━ 스펙 불일치 있음 — 이대로는 재인코딩 없이 붙지 않는다 ━━━"]
        if !trackGaps.isEmpty {
            lines.append("    트랙 누락 \(trackGaps.count)종: "
                         + trackGaps.joined(separator: ", ")
                         + " — 일부 클립에만 존재")
        }
        if !valueMismatches.isEmpty {
            lines.append("    값 불일치 \(valueMismatches.count)개: "
                         + valueMismatches.joined(separator: ", "))
        }
        return lines
    }
}

// MARK: - 포맷 헬퍼

/// 소수부가 없으면 정수로. 1080.0 → "1080"
private func num(_ value: CGFloat) -> String {
    value == value.rounded()
        ? String(format: "%.0f", value)
        : String(format: "%.3f", value)
}

private func isUsable(_ time: CMTime) -> Bool {
    time.isValid && time.isNumeric && time.value > 0 && time.timescale > 0
}

/// 판정용. 기약분수로 줄여서 1/30 · 2/60 · 20/600 이 같은 키가 되게 한다.
/// 기기·포맷에 따라 timescale 이 600 / 30000 / 90000 등으로 갈리므로
/// value/timescale 을 그대로 비교하면 같은 30fps 클립이 불일치로 잡힌다.
private func frameDurationKey(_ time: CMTime) -> String {
    guard isUsable(time) else {
        return "무효:\(time.value)/\(time.timescale):\(time.flags.rawValue)"
    }
    let divisor = greatestCommonDivisor(Int64(time.value), Int64(time.timescale))
    return "\(Int64(time.value) / divisor)/\(Int64(time.timescale) / divisor)"
}

/// 표시용. 원본 value/timescale 을 그대로 보여준다.
private func frameDurationText(_ time: CMTime) -> String {
    guard isUsable(time) else {
        return "(무효: \(time.value)/\(time.timescale))"
    }
    return String(format: "%d/%d  (%.3f fps)",
                  time.value, time.timescale, 1 / time.seconds)
}

private func greatestCommonDivisor(_ a: Int64, _ b: Int64) -> Int64 {
    var x = abs(a)
    var y = abs(b)
    while y != 0 { (x, y) = (y, x % y) }
    return x == 0 ? 1 : x
}

/// preferredTransform 의 회전각을 0 / 90 / 180 / 270 로 정규화한다.
///
/// 병합 그룹을 나누는 기준이다. 파일명이 아니라 이 값으로 묶어야
/// "묶는 기준"과 "붙을 수 있는지 판정하는 기준"이 일치한다.
func rotationAngleDegrees(of transform: CGAffineTransform) -> Int {
    let radians = atan2(Double(transform.b), Double(transform.a))
    let degrees = radians * 180 / .pi
    let normalized = (degrees.rounded() + 360).truncatingRemainder(dividingBy: 360)
    return Int(normalized)
}

extension ClipSpec.Video {
    var rotationDegrees: Int { rotationAngleDegrees(of: preferredTransform) }
}

extension ClipSpec {
    /// 비디오를 읽지 못했으면 nil. 그룹핑에서 제외해야 한다.
    var videoRotationDegrees: Int? { video.spec?.rotationDegrees }
}

/// 여섯 값 그대로 + 회전각. 1-11(회전 정보 일치 확인)에서 각도가 바로 필요하다.
private func transformText(_ t: CGAffineTransform) -> String {
    let values = [t.a, t.b, t.c, t.d, t.tx, t.ty].map(num).joined(separator: " ")
    return "[\(values)]  \(rotationAngleDegrees(of: t))°"
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
