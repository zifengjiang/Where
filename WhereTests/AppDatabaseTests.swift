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
    func v1SchemaHasExpectedColumnsAndNullability() throws {
        let database = try AppDatabase.inMemory()

        try database.writer.read { db in
            let expectedColumns: [String: Set<String>] = [
                "scene": ["id", "name", "imagePath", "createdAt", "updatedAt"],
                "item": [
                    "id", "sceneID", "name", "locationNote",
                    "appearanceOriginalImagePath", "appearanceCutoutImagePath", "note",
                    "normalizedX", "normalizedY", "createdAt", "updatedAt",
                ],
                "itemAlias": ["id", "itemID", "value", "normalizedValue", "createdAt"],
                "tag": ["id", "name", "normalizedName", "createdAt", "updatedAt"],
                "itemTag": ["itemID", "tagID", "createdAt"],
            ]

            for (table, expected) in expectedColumns {
                let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
                let columns = Set(rows.map { $0["name"] as String })
                #expect(columns == expected)
            }

            let sceneColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(scene)")
            let imagePath = try #require(sceneColumns.first { ($0["name"] as String) == "imagePath" })
            #expect((imagePath["notnull"] as Int) == 1)

            let itemColumns = try Row.fetchAll(db, sql: "PRAGMA table_info(item)")
            let locationNote = try #require(itemColumns.first { ($0["name"] as String) == "locationNote" })
            #expect((locationNote["notnull"] as Int) == 0)
        }
    }

    @Test
    func itemLocationNoteAcceptsNull() throws {
        let database = try AppDatabase.inMemory()
        let now = Date()

        try database.writer.write { db in
            try insertScene(db, now: now)
            try insertItem(db, locationNote: nil, now: now)
        }
    }

    @Test(arguments: [(-0.01, 0.5), (1.01, 0.5), (0.5, -0.01), (0.5, 1.01)])
    func normalizedCoordinatesOutsideUnitRangeAreRejected(x: Double, y: Double) throws {
        let database = try AppDatabase.inMemory()
        let now = Date()

        try database.writer.write { db in
            try insertScene(db, now: now)
            #expect(throws: DatabaseError.self) {
                try insertItem(db, normalizedX: x, normalizedY: y, now: now)
            }
        }
    }

    @Test
    func uniqueConstraintsRejectDuplicateAliasesTagsAndJoins() throws {
        let database = try AppDatabase.inMemory()
        let now = Date()

        try database.writer.write { db in
            try insertScene(db, now: now)
            try insertItem(db, now: now)
            try db.execute(
                sql: "INSERT INTO itemAlias (id, itemID, value, normalizedValue, createdAt) VALUES (?, ?, ?, ?, ?)",
                arguments: ["alias-1", "item-1", "Keys", "keys", now]
            )
            #expect(throws: DatabaseError.self) {
                try db.execute(
                    sql: "INSERT INTO itemAlias (id, itemID, value, normalizedValue, createdAt) VALUES (?, ?, ?, ?, ?)",
                    arguments: ["alias-2", "item-1", "Spare keys", "keys", now]
                )
            }

            try db.execute(
                sql: "INSERT INTO tag (id, name, normalizedName, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)",
                arguments: ["tag-1", "Daily", "daily", now, now]
            )
            #expect(throws: DatabaseError.self) {
                try db.execute(
                    sql: "INSERT INTO tag (id, name, normalizedName, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)",
                    arguments: ["tag-2", "Everyday", "daily", now, now]
                )
            }

            try db.execute(
                sql: "INSERT INTO itemTag (itemID, tagID, createdAt) VALUES (?, ?, ?)",
                arguments: ["item-1", "tag-1", now]
            )
            #expect(throws: DatabaseError.self) {
                try db.execute(
                    sql: "INSERT INTO itemTag (itemID, tagID, createdAt) VALUES (?, ?, ?)",
                    arguments: ["item-1", "tag-1", now]
                )
            }
        }
    }

    @Test
    func foreignKeysRejectOrphanRows() throws {
        let database = try AppDatabase.inMemory()
        let now = Date()

        try database.writer.write { db in
            #expect(throws: DatabaseError.self) {
                try insertItem(db, sceneID: "missing-scene", now: now)
            }
            #expect(throws: DatabaseError.self) {
                try db.execute(
                    sql: "INSERT INTO itemAlias (id, itemID, value, normalizedValue, createdAt) VALUES (?, ?, ?, ?, ?)",
                    arguments: ["alias-1", "missing-item", "Keys", "keys", now]
                )
            }
            #expect(throws: DatabaseError.self) {
                try db.execute(
                    sql: "INSERT INTO itemTag (itemID, tagID, createdAt) VALUES (?, ?, ?)",
                    arguments: ["missing-item", "missing-tag", now]
                )
            }
        }
    }

    @Test
    func v1CreatesRequestedIndexes() throws {
        let database = try AppDatabase.inMemory()

        try database.writer.read { db in
            let indexes = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'index'"
            )
            #expect(Set([
                "item_on_sceneID",
                "itemAlias_on_normalizedValue",
                "tag_on_normalizedName",
                "item_on_updatedAt",
            ]).isSubset(of: Set(indexes)))
        }
    }

    @Test
    func deletingSceneCascadesThroughTheEntireItemGraph() throws {
        let database = try AppDatabase.inMemory()
        let now = Date()

        try database.writer.write { db in
            try db.execute(
                sql: "INSERT INTO scene (id, name, imagePath, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)",
                arguments: ["scene-1", "Home", "scenes/home.jpg", now, now]
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

    private func insertScene(_ db: Database, now: Date) throws {
        try db.execute(
            sql: "INSERT INTO scene (id, name, imagePath, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)",
            arguments: ["scene-1", "Home", "scenes/home.jpg", now, now]
        )
    }

    private func insertItem(
        _ db: Database,
        sceneID: String = "scene-1",
        locationNote: String? = "Bowl",
        normalizedX: Double = 0.25,
        normalizedY: Double = 0.75,
        now: Date
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO item (
                    id, sceneID, name, locationNote,
                    appearanceOriginalImagePath, appearanceCutoutImagePath, note,
                    normalizedX, normalizedY, createdAt, updatedAt
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: ["item-1", sceneID, "Keys", locationNote, nil, nil, nil, normalizedX, normalizedY, now, now]
        )
    }
}
