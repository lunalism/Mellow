import Foundation

struct RelativeMediaPath: Codable, Hashable, Sendable {
    let value: String

    init(_ value: String) throws {
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
        else {
            throw DomainValidationError.invalidMediaRelativePath
        }

        self.value = value
    }
}
