import Foundation
import CoreGraphics

/// `.cube` (Adobe/Resolve 3D LUT) 파서 — 크기 동적, **로케일 안전** (Stage L1).
///
/// 설계 원칙:
/// - `LUT_3D_SIZE`를 파일에서 읽는다. N을 하드코딩하지 않는다(32·33·64 혼재).
/// - float은 오직 `Float(substring)`으로만 파싱한다. `NumberFormatter` 금지 —
///   콤마 소수 로케일(예: fr_FR)에서 깨진다. `Float`/`Double` 초기자는 로케일 독립적.
/// - `.cube`의 네이티브 RED-fastest 순서를 그대로 복사(축 스왑 없음 — L2에서 픽셀 검증됨).
enum CubeParser {

    enum ParseError: Error, CustomStringConvertible {
        case empty
        case missingSize
        case unsupported1DLUT
        case sizeOutOfRange(Int)
        case malformedLine(Int)
        case valueCountMismatch(expected: Int, got: Int)

        var description: String {
            switch self {
            case .empty:                            return "empty file"
            case .missingSize:                      return "missing LUT_3D_SIZE"
            case .unsupported1DLUT:                 return "unsupported 1D LUT"
            case .sizeOutOfRange(let n):            return "size out of range (\(n))"
            case .malformedLine(let i):             return "malformed line \(i)"
            case .valueCountMismatch(let e, let g): return "value count mismatch (expected \(e), got \(g))"
            }
        }
    }

    static func parse(_ text: String, colorSpace: CGColorSpace) throws -> LUTCube {
        // 완전 공백/빈 파일은 즉시 거부.
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ParseError.empty
        }

        // CRLF/CR을 LF로 정규화한 뒤, 빈 줄을 보존하며 분할(줄 번호 유지).
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)

        var size: Int?
        var sawOneDSize = false
        var domainMin: [Float] = [0, 0, 0]
        var domainMax: [Float] = [1, 1, 1]
        var floats: [Float] = []

        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // 빈 줄과 '#' 주석은 건너뛴다.
            if line.isEmpty || line.hasPrefix("#") { continue }

            // 탭/스페이스 혼용을 허용하며 토큰화.
            let tokens = line.split(whereSeparator: { $0.isWhitespace })
            guard let first = tokens.first else { continue }

            // 데이터 줄은 첫 토큰이 숫자. 비숫자 첫 토큰 = 키워드 줄.
            if Float(first) == nil {
                switch first.uppercased() {
                case "LUT_3D_SIZE":
                    if tokens.count >= 2, let n = Int(tokens[1]) { size = n }
                case "LUT_1D_SIZE":
                    sawOneDSize = true
                case "DOMAIN_MIN":
                    if let v = parseTriple(tokens.dropFirst()) { domainMin = v }
                case "DOMAIN_MAX":
                    if let v = parseTriple(tokens.dropFirst()) { domainMax = v }
                default:
                    // TITLE, LUT_3D_INPUT_RANGE, 기타 미상 키워드는 무시(데이터로 오독 금지).
                    break
                }
                continue
            }

            // 데이터 줄: 정확히 3개 float. 아니면 malformed.
            guard tokens.count == 3,
                  let r = Float(tokens[0]),
                  let g = Float(tokens[1]),
                  let b = Float(tokens[2]) else {
                throw ParseError.malformedLine(lineNumber)
            }

            // size를 처음 알게 되면 용량 예약(64³×4 ≈ 4M float).
            if floats.isEmpty, let n = size {
                floats.reserveCapacity(n * n * n * 4)
            }

            floats.append(clamp01(r))
            floats.append(clamp01(g))
            floats.append(clamp01(b))
            floats.append(1.0)
        }

        // 크기 결정 / 1D 거부.
        guard let n = size else {
            if sawOneDSize { throw ParseError.unsupported1DLUT }
            throw ParseError.missingSize
        }
        guard (2...64).contains(n) else { throw ParseError.sizeOutOfRange(n) }

        // 도메인은 CIColorCube가 0..1을 가정 — 비단위면 경고(무음 진행 금지).
        if !isApproximately(domainMin, [0, 0, 0]) || !isApproximately(domainMax, [1, 1, 1]) {
            print("[LUT] non-unit domain min=\(domainMin) max=\(domainMax) — CIColorCube assumes 0..1")
        }

        // 값 개수 검증.
        let expectedTriples = n * n * n
        let gotTriples = floats.count / 4
        guard gotTriples == expectedTriples else {
            throw ParseError.valueCountMismatch(expected: expectedTriples, got: gotTriples)
        }

        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        return LUTCube(dimension: n, data: data, colorSpace: colorSpace)
    }

    // MARK: - Helpers

    private static func clamp01(_ x: Float) -> Float { min(max(x, 0), 1) }

    /// 세 토큰을 float 3개로. 3개 미만이거나 파싱 실패면 nil(그레이스풀).
    private static func parseTriple(_ tokens: ArraySlice<Substring>) -> [Float]? {
        let vals = tokens.prefix(3).compactMap { Float($0) }
        return vals.count == 3 ? vals : nil
    }

    /// 1e-4 이내 근사 동일.
    private static func isApproximately(_ a: [Float], _ b: [Float]) -> Bool {
        guard a.count == b.count else { return false }
        for (x, y) in zip(a, b) where abs(x - y) > 1e-4 { return false }
        return true
    }
}
