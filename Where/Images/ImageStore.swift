import Foundation

actor ImageStore {
    let rootDirectory: URL

    init(rootDirectory: URL) throws {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        self.rootDirectory = rootDirectory
    }
}
