import Foundation

struct AppDependencies: Sendable {
    let database: AppDatabase
    let imageStore: ImageStore
    let sceneRepository: any SceneRepositoryProtocol
    let itemRepository: any ItemRepositoryProtocol

    static func production() async throws -> AppDependencies {
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let dependencies = try makeProduction()
            try Task.checkCancellation()
            return dependencies
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func makeProduction(fileManager: FileManager = .default) throws -> AppDependencies {
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
        let sceneRepository = SceneRepository(database: database)
        return AppDependencies(
            database: database,
            imageStore: try ImageStore(rootDirectory: rootDirectory),
            sceneRepository: sceneRepository,
            itemRepository: ItemRepository(
                database: database,
                sceneRepository: sceneRepository
            )
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
        let sceneRepository = SceneRepository(database: database)
        return try AppDependencies(
            database: database,
            imageStore: ImageStore(rootDirectory: rootDirectory),
            sceneRepository: sceneRepository,
            itemRepository: ItemRepository(
                database: database,
                sceneRepository: sceneRepository
            )
        )
    }
}
