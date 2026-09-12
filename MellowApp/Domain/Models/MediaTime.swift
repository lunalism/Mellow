import CoreMedia

struct MediaTime: Codable, Hashable, Comparable, Sendable {
    let value: Int64
    let timescale: Int32

    init(value: Int64, timescale: Int32) throws {
        guard timescale > 0 else {
            throw DomainValidationError.invalidTimeScale
        }

        self.value = value
        self.timescale = timescale
    }

    static let zero = try! MediaTime(value: 0, timescale: 600)

    static func seconds(_ value: Int64) -> MediaTime {
        try! MediaTime(value: value, timescale: 1)
    }

    static func < (lhs: MediaTime, rhs: MediaTime) -> Bool {
        CMTimeCompare(lhs.cmTime, rhs.cmTime) < 0
    }

    static func + (lhs: MediaTime, rhs: MediaTime) -> MediaTime {
        let sum = CMTimeAdd(lhs.cmTime, rhs.cmTime)
        return try! MediaTime(value: sum.value, timescale: sum.timescale)
    }

    private var cmTime: CMTime {
        CMTime(value: value, timescale: timescale)
    }
}
