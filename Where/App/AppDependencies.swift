import Foundation

struct AppDependencies: Sendable {
    let database: AppDatabase
    let imageStore: ImageStore
    let sceneRepository: any SceneRepositoryProtocol
    let itemRepository: any ItemRepositoryProtocol

    static func production(fileManager: FileManager = .default) throws -> AppDependencies {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let rootDirectory = applicationSupport.appending(
            path: "Where",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let database = try AppDatabase(
            path: rootDirectory.appending(path: "where.sqlite").path
        )
        return AppDependencies(
            database: database,
            imageStore: try ImageStore(rootDirectory: rootDirectory),
            sceneRepository: SceneRepository(database: database),
            itemRepository: ItemRepository(database: database)
        )
    }

    static func testing() throws -> AppDependencies {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )

        let database = try AppDatabase.inMemory()
        return try AppDependencies(
            database: database,
            imageStore: ImageStore(rootDirectory: rootDirectory),
            sceneRepository: SceneRepository(database: database),
            itemRepository: ItemRepository(database: database)
        )
    }
}
