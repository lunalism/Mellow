import Foundation
import SwiftData

enum MellowModelContainer {
    static let shared: ModelContainer = {
        do {
            return try makePersistentContainer()
        } catch {
            fatalError("Unable to create Mellow metadata persistence: \(error)")
        }
    }()

    static func makePersistentContainer(storeURL: URL? = nil) throws -> ModelContainer {
        let schema = Schema([PersistedVlogProject.self, PersistedVlogClip.self])
        let configuration: ModelConfiguration

        if let storeURL {
            configuration = ModelConfiguration(url: storeURL)
        } else {
            configuration = ModelConfiguration(schema: schema)
        }

        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
