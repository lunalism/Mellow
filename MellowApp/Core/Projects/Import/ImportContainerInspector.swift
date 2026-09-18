import Foundation

/// Bounded, read-only ISO BMFF / QuickTime container identification from the file's own bytes
/// (ADR-044: the extension, UTType and Photos metadata never decide). Observation only — the
/// preflight classifier decides eligibility.
///
/// Rule: walk top-level boxes inside a bounded prefix. The first `ftyp` box found classifies the
/// file (`qt  ` as major or compatible brand → QuickTime; any other brand set → ISO Base Media).
/// A recognised non-ISO signature (EBML/Matroska, RIFF, MPEG-TS) → `.other`. Anything that does
/// not parse as boxes, or parses without an `ftyp` inside the prefix, → `.unknown` (never guessed
/// as QuickTime).
enum ImportContainerInspector {
    /// Largest prefix examined; `ftyp` is required to be near the start of a valid file, and this
    /// also bounds allocation regardless of what the size fields claim.
    static let maximumPrefixBytes = 64 * 1024
    static let maximumBoxesScanned = 16

    static func classify(fileURL: URL) throws -> ImportContainer {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: maximumPrefixBytes) ?? Data()
        return classify(prefix: prefix)
    }

    static func classify(prefix: Data) -> ImportContainer {
        let bytes = [UInt8](prefix)
        if let signature = nonISOSignature(bytes) { return .other(signature) }
        var offset = 0
        var scanned = 0
        while offset + 8 <= bytes.count, scanned < maximumBoxesScanned {
            scanned += 1
            let size32 = UInt32(bigEndian: bytes[offset..<offset + 4])
            let type = String(bytes: bytes[offset + 4..<offset + 8], encoding: .isoLatin1) ?? "????"
            var headerLength = 8
            var boxLength: UInt64
            switch size32 {
            case 0:
                boxLength = UInt64(bytes.count - offset)   // "to end of file" — bounded by the prefix
            case 1:
                guard offset + 16 <= bytes.count else { return .unknown }
                boxLength = UInt64(bigEndian: bytes[offset + 8..<offset + 16])
                headerLength = 16
            default:
                boxLength = UInt64(size32)
            }
            guard boxLength >= UInt64(headerLength) else { return .unknown }
            if type == "ftyp" {
                let payloadStart = offset + headerLength
                let payloadEnd = min(bytes.count, offset + Int(min(boxLength, UInt64(bytes.count))))
                guard payloadEnd - payloadStart >= 8 else { return .unknown }   // major + minor version
                var brands: [String] = []
                var cursor = payloadStart
                while cursor + 4 <= payloadEnd {
                    if cursor == payloadStart + 4 { cursor += 4; continue }   // minor version
                    brands.append(String(bytes: bytes[cursor..<cursor + 4], encoding: .isoLatin1) ?? "????")
                    cursor += 4
                }
                guard !brands.isEmpty else { return .unknown }
                return brands.contains("qt  ") ? .quickTime : .isoBaseMedia(brands: brands)
            }
            // Only well-formed, plausible box types keep the walk going (e.g. `wide`, `free`, `skip`,
            // `mdat` before a late `ftyp`); anything else is not an ISO family file.
            guard type.utf8.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return .unknown }
            guard boxLength <= UInt64(Int.max), Int(boxLength) <= bytes.count - offset else { return .unknown }
            offset += Int(boxLength)
        }
        return .unknown
    }

    private static func nonISOSignature(_ b: [UInt8]) -> String? {
        if b.count >= 4, b[0] == 0x1A, b[1] == 0x45, b[2] == 0xDF, b[3] == 0xA3 { return "EBML" }
        if b.count >= 4, b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46 { return "RIFF" }
        if b.count >= 4, b[0] == 0x47, b[1] == 0x47 || (b.count >= 189 && b[188] == 0x47) { return "MPEG-TS" }
        return nil
    }
}

private extension FixedWidthInteger {
    init(bigEndian slice: ArraySlice<UInt8>) {
        var value: Self = 0
        for byte in slice { value = (value << 8) | Self(byte) }
        self = value
    }
}
