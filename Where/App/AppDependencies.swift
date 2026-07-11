import Foundation

struct AppDependencies {
    let database: AppDatabase
    let imageStore: ImageStore

    static func testing() throws -> AppDependencies {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )

        return try AppDependencies(
            database: AppDatabase.inMemory(),
            imageStore: ImageStore(rootDirectory: rootDirectory)
        )
    }
}
