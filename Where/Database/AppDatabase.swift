import GRDB

final class AppDatabase: @unchecked Sendable {
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    static func inMemory() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue())
    }
}
