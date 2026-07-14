import Foundation
import CoreGraphics
import CryptoKit

// ─────────────────────────────────────────────────────────────────────────────
// .lutbin FORMAT v1  — fixed 12-byte header, then raw payload.
//
//   offset  size  field       notes
//   ------  ----  ----------  ----------------------------------------------
//        0     4  magic       ASCII "MLUT" (0x4D 0x4C 0x55 0x54)
//        4     4  version     UInt32, little-endian, == 1
//        8     4  dimension   UInt32, little-endian, n (2...64)
//       12     -  payload     n³ × 4 × Float32, little-endian, RGBA interleaved,
//                             RED fastest axis, A = 1.0 — i.e. LUTCube.data VERBATIM
//
//   payload byte length MUST equal n*n*n*4*4  (= n³ × 16)
//   total file size     = 12 + n³ × 16
//
//   Payload begins at offset 12 (4-byte aligned). colorSpace is NOT serialized:
//   it is always sRGB and is reconstructed at runtime via CGColorSpace(name: .sRGB).
//   The runtime reader lives in LUTStore.loadCube(forSlug:) — keep the two in sync.
// ─────────────────────────────────────────────────────────────────────────────

enum LutBin {
    static let magic: [UInt8] = Array("MLUT".utf8)
    static let version: UInt32 = 1
    static let headerSize = 12

    /// LUTCube → .lutbin bytes. Payload is cube.data copied verbatim (no transform).
    static func serialize(dimension: Int, payload: Data) -> Data {
        var out = Data(capacity: headerSize + payload.count)
        out.append(contentsOf: magic)
        withUnsafeBytes(of: version.littleEndian) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(dimension).littleEndian) { out.append(contentsOf: $0) }
        out.append(payload)
        return out
    }

    struct DecodeError: Error, CustomStringConvertible {
        let description: String
    }

    /// .lutbin bytes → (dimension, payload). Validates magic, version, and length invariant.
    static func deserialize(_ blob: Data) throws -> (dimension: Int, payload: Data) {
        guard blob.count >= headerSize else {
            throw DecodeError(description: "truncated: \(blob.count) < \(headerSize) byte header")
        }
        let bytes = [UInt8](blob.prefix(headerSize))
        guard Array(bytes[0..<4]) == magic else {
            throw DecodeError(description: "bad magic \(Array(bytes[0..<4]))")
        }
        let ver = UInt32(littleEndian: bytes[4..<8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        guard ver == version else { throw DecodeError(description: "unsupported version \(ver)") }
        let dim = Int(UInt32(littleEndian: bytes[8..<12].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
        guard (2...64).contains(dim) else { throw DecodeError(description: "dimension out of range \(dim)") }

        let payload = Data(blob.dropFirst(headerSize))
        let expected = dim * dim * dim * 4 * MemoryLayout<Float>.size
        guard payload.count == expected else {
            throw DecodeError(description: "payload \(payload.count) != expected \(expected) for n=\(dim)")
        }
        return (dim, payload)
    }
}

// MARK: - helpers for reporting

func sha256(_ d: Data) -> String {
    SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
}

// MARK: - run

// usage: lutconv <srcDir with .cube> <outDir for .lutbin>
guard CommandLine.arguments.count > 2 else {
    print("usage: lutconv <srcDir> <outDir>")
    exit(2)
}
let srcDir = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { fatalError("no sRGB") }

let cubes = try FileManager.default.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension.lowercased() == "cube" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

guard !cubes.isEmpty else {
    print("no .cube files in \(srcDir.path)")
    exit(2)
}

var totalCube = 0, totalBin = 0, failures = 0

print("lutconv — .cube → .lutbin v1, with byte-identical round-trip verification")
print(String(repeating: "─", count: 78))

for url in cubes {
    let name = url.deletingPathExtension().lastPathComponent
    let cubeBytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0) ?? 0
    totalCube += cubeBytes

    // ground truth — the app's REAL parser (compiled in from Mellow/Camera/)
    let text = try String(contentsOf: url, encoding: .utf8)
    let truth = try CubeParser.parse(text, colorSpace: sRGB)

    // serialize → write → read back → deserialize → compare
    let blob = LutBin.serialize(dimension: truth.dimension, payload: truth.data)
    let outURL = outDir.appendingPathComponent(name + ".lutbin")
    try blob.write(to: outURL)
    let readBack = try Data(contentsOf: outURL)
    let (recoveredDim, recoveredPayload) = try LutBin.deserialize(readBack)
    totalBin += readBack.count

    let pass = recoveredPayload == truth.data                 // byte for byte
        && recoveredDim == truth.dimension
        && sha256(recoveredPayload) == sha256(truth.data)
    if !pass { failures += 1 }

    print("\(pass ? "PASS" : "FAIL")  \(name)  N=\(truth.dimension)  \(cubeBytes)B → \(readBack.count)B")
}

print(String(repeating: "─", count: 78))
func mb(_ b: Int) -> String { String(format: "%.2f MB", Double(b) / 1_048_576) }
print("converted: \(cubes.count)   failures: \(failures)   \(mb(totalCube)) .cube → \(mb(totalBin)) .lutbin")
print("output: \(outDir.path)")
if failures > 0 {
    print("\n*** \(failures) CUBE(S) FAILED ROUND-TRIP — DO NOT SHIP THESE BLOBS ***")
    exit(1)
}
