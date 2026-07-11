import Foundation
import GRDB
import Testing
@testable import Where

struct AppDatabaseTests {
    @Test
    func v1MigrationCreatesExpectedTablesAndEnablesForeignKeys() throws {
        let database = try AppDatabase.inMemory()

        try database.writer.read { db in
            let foreignKeys = try Int.fetchOne(db, sql: "PRAGMA foreign_keys")
            #expect(foreignKeys == 1)

            let tables = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
            #expect(Set(["scene", "item", "itemAlias", "tag", "itemTag"]).isSubset(of: Set(tables)))
        }
    }

    @Test
    func deletingSceneCascadesThroughTheEntireItemGraph() throws {
        let database = try AppDatabase.inMemory()
        let now = Date()

        try database.writer.write { db in
            try db.execute(
                sql: "INSERT INTO scene (id, name, createdAt, updatedAt) VALUES (?, ?, ?, ?)",
                arguments: ["scene-1", "Home", now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO item (
                        id, sceneID, name, locationNote,
                        appearanceOriginalImagePath, appearanceCutoutImagePath, note,
                        normalizedX, normalizedY, createdAt, updatedAt
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: ["item-1", "scene-1", "Keys", "Bowl", nil, nil, nil, 0.25, 0.75, now, now]
            )
            try db.execute(
                sql: "INSERT INTO itemAlias (id, itemID, value, normalizedValue, createdAt) VALUES (?, ?, ?, ?, ?)",
                arguments: ["alias-1", "item-1", "Door keys", "door keys", now]
            )
            try db.execute(
                sql: "INSERT INTO tag (id, name, normalizedName, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)",
                arguments: ["tag-1", "Daily", "daily", now, now]
            )
            try db.execute(
                sql: "INSERT INTO itemTag (itemID, tagID, createdAt) VALUES (?, ?, ?)",
                arguments: ["item-1", "tag-1", now]
            )

            try db.execute(sql: "DELETE FROM scene WHERE id = ?", arguments: ["scene-1"])

            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item") == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM itemAlias") == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM itemTag") == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tag") == 1)
        }
    }
}
