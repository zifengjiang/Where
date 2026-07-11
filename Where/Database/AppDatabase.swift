import Foundation
import GRDB

final class AppDatabase: @unchecked Sendable {
    let writer: any DatabaseWriter

    private init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    convenience init(path: String) throws {
        try self.init(writer: DatabaseQueue(path: path, configuration: Self.configuration))
    }

    static func inMemory() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue(configuration: configuration))
    }

    private static var configuration: Configuration {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return configuration
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "scene") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("imagePath", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "item") { table in
                table.column("id", .text).primaryKey()
                table.column("sceneID", .text).notNull()
                    .references("scene", onDelete: .cascade)
                table.column("name", .text).notNull()
                table.column("locationNote", .text)
                table.column("appearanceOriginalImagePath", .text)
                table.column("appearanceCutoutImagePath", .text)
                table.column("note", .text)
                table.column("normalizedX", .double).notNull()
                    .check(sql: "normalizedX BETWEEN 0 AND 1")
                table.column("normalizedY", .double).notNull()
                    .check(sql: "normalizedY BETWEEN 0 AND 1")
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "item_on_sceneID", on: "item", columns: ["sceneID"])
            try db.create(index: "item_on_updatedAt", on: "item", columns: ["updatedAt"])

            try db.create(table: "itemAlias") { table in
                table.column("id", .text).primaryKey()
                table.column("itemID", .text).notNull()
                    .references("item", onDelete: .cascade)
                table.column("value", .text).notNull()
                table.column("normalizedValue", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.uniqueKey(["itemID", "normalizedValue"])
            }
            try db.create(index: "itemAlias_on_normalizedValue", on: "itemAlias", columns: ["normalizedValue"])

            try db.create(table: "tag") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("normalizedName", .text).notNull().unique()
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "tag_on_normalizedName", on: "tag", columns: ["normalizedName"])

            try db.create(table: "itemTag") { table in
                table.column("itemID", .text).notNull()
                    .references("item", onDelete: .cascade)
                table.column("tagID", .text).notNull()
                    .references("tag", onDelete: .cascade)
                table.column("createdAt", .datetime).notNull()
                table.primaryKey(["itemID", "tagID"])
            }
        }
        return migrator
    }
}
