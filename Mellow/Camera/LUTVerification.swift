#if DEBUG
import Foundation
import CoreGraphics

/// DEBUG 전용 구조 검증 하네스 (Stage L1).
///
/// 번들의 9개 `.cube`를 모두 파싱해서 크기·값 개수·채널 범위를 콘솔에 찍는다.
/// 앱 파이프라인엔 영향 없음 — 실행 시 백그라운드 큐에서 한 번만 호출.
enum LUTVerification {

    static func runParseCheck() {
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else {
            print("[LUT] sRGB color space unavailable — skipping check")
            return
        }

        for entry in MellowFilterRoster.entries {
            guard let url = Bundle.main.url(forResource: entry.fileName, withExtension: "cube") else {
                print("[LUT] MISSING \(entry.fileName)")
                continue
            }

            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let cube = try CubeParser.parse(text, colorSpace: sRGB)

                let n = cube.dimension
                let expected = n * n * n * 4
                let (count, lo, hi) = scan(cube.data)
                let verdict = (count == expected) ? "OK" : "FAIL"

                print("[LUT] \(entry.slug) N=\(n) floats=\(count) expected=\(expected) \(verdict) range=[\(lo),\(hi)]")
            } catch {
                print("[LUT] PARSE FAIL \(entry.slug): \(error)")
            }
        }
    }

    /// 버퍼의 float 개수와 최소·최대 채널 값을 스캔.
    private static func scan(_ data: Data) -> (count: Int, min: Float, max: Float) {
        data.withUnsafeBytes { raw -> (Int, Float, Float) in
            let buffer = raw.bindMemory(to: Float.self)
            guard !buffer.isEmpty else { return (0, 0, 0) }
            var lo = buffer[0]
            var hi = buffer[0]
            for v in buffer {
                if v < lo { lo = v }
                if v > hi { hi = v }
            }
            return (buffer.count, lo, hi)
        }
    }
}
#endif
