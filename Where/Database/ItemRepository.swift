import Foundation
import GRDB

protocol ItemRepositoryProtocol: Sendable {
    func saveSceneDraft(_ draft: SceneDraft) async throws
    func searchItems(query: String) async throws -> [ItemSummary]
    func observeItems(query: String) -> AsyncThrowingStream<[ItemSummary], Error>
    func deleteItem(id: UUID) async throws -> DeletedImagePaths
}

final class ItemRepository: ItemRepositoryProtocol, Sendable {
    enum ReadQuery: Sendable, Equatable {
        case items
        case aliases
        case tags
    }

    private let database: AppDatabase
    private let queryDidExecute: @Sendable (ReadQuery) -> Void
    let sceneRepository: SceneRepository

    init(
        database: AppDatabase,
        queryDidExecute: @escaping @Sendable (ReadQuery) -> Void = { _ in }
    ) {
        self.database = database
        self.queryDidExecute = queryDidExecute
        self.sceneRepository = SceneRepository(database: database)
    }

    func saveSceneDraft(_ draft: SceneDraft) async throws {
        let now = Date()
        try await database.writer.write { db in
            let sceneID = draft.id.uuidString
            let sceneCreatedAt = try Date.fetchOne(
                db, sql: "SELECT createdAt FROM scene WHERE id = ?", arguments: [sceneID]) ?? now
            try db.execute(sql: """
                INSERT INTO scene (id, name, imagePath, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, imagePath = excluded.imagePath,
                    updatedAt = excluded.updatedAt
                """, arguments: [sceneID, draft.name, draft.imagePath, sceneCreatedAt, now])

            let retainedIDs = Set(draft.items.map { $0.id.uuidString })
            let existingIDs = try String.fetchAll(
                db, sql: "SELECT id FROM item WHERE sceneID = ?", arguments: [sceneID])
            for id in existingIDs where !retainedIDs.contains(id) {
                try db.execute(sql: "DELETE FROM item WHERE id = ?", arguments: [id])
            }

            for item in draft.items {
                try Self.save(item, sceneID: sceneID, now: now, db: db)
            }
            try db.execute(sql: "DELETE FROM tag WHERE NOT EXISTS (SELECT 1 FROM itemTag WHERE itemTag.tagID = tag.id)")
        }
    }

    func searchItems(query: String) async throws -> [ItemSummary] {
        let normalizedQuery = SearchNormalizer.normalize(query)
        let queryDidExecute = queryDidExecute
        return try await database.writer.read { db in
            try Self.fetchItems(db, normalizedQuery: normalizedQuery, queryDidExecute: queryDidExecute)
        }
    }

    func observeItems(query: String) -> AsyncThrowingStream<[ItemSummary], Error> {
        let normalizedQuery = SearchNormalizer.normalize(query)
        let queryDidExecute = queryDidExecute
        let writer = database.writer
        let observation = ValueObservation.tracking { db in
            try Self.fetchItems(db, normalizedQuery: normalizedQuery, queryDidExecute: queryDidExecute)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in observation.values(in: writer) {
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func deleteItem(id: UUID) async throws -> DeletedImagePaths {
        try await database.writer.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT appearanceOriginalImagePath, appearanceCutoutImagePath FROM item WHERE id = ?",
                arguments: [id.uuidString])
            else { throw RepositoryError.notFound }
            let paths = DeletedImagePaths(
                original: row["appearanceOriginalImagePath"], cutout: row["appearanceCutoutImagePath"])
            try db.execute(sql: "DELETE FROM item WHERE id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM tag WHERE NOT EXISTS (SELECT 1 FROM itemTag WHERE itemTag.tagID = tag.id)")
            return paths
        }
    }

    private static func save(_ item: ItemDraft, sceneID: String, now: Date, db: Database) throws {
        let itemID = item.id.uuidString
        let createdAt = try Date.fetchOne(
            db, sql: "SELECT createdAt FROM item WHERE id = ?", arguments: [itemID]) ?? now
        try db.execute(sql: """
            INSERT INTO item (
                id, sceneID, name, locationNote, appearanceOriginalImagePath,
                appearanceCutoutImagePath, note, normalizedX, normalizedY, createdAt, updatedAt
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET sceneID = excluded.sceneID, name = excluded.name,
                locationNote = excluded.locationNote,
                appearanceOriginalImagePath = excluded.appearanceOriginalImagePath,
                appearanceCutoutImagePath = excluded.appearanceCutoutImagePath, note = excluded.note,
                normalizedX = excluded.normalizedX, normalizedY = excluded.normalizedY,
                updatedAt = excluded.updatedAt
            """, arguments: [
                itemID, sceneID, item.name, item.locationNote, item.appearanceOriginalImagePath,
                item.appearanceCutoutImagePath, item.note, item.normalizedX, item.normalizedY, createdAt, now,
            ])

        try db.execute(sql: "DELETE FROM itemAlias WHERE itemID = ?", arguments: [itemID])
        var aliases: [String: String] = [:]
        for alias in item.aliases {
            let normalized = SearchNormalizer.normalize(alias)
            if !normalized.isEmpty, aliases[normalized] == nil { aliases[normalized] = alias }
        }
        for normalized in aliases.keys.sorted() {
            try db.execute(
                sql: "INSERT INTO itemAlias (id, itemID, value, normalizedValue, createdAt) VALUES (?, ?, ?, ?, ?)",
                arguments: [UUID().uuidString, itemID, aliases[normalized]!, normalized, now])
        }

        try db.execute(sql: "DELETE FROM itemTag WHERE itemID = ?", arguments: [itemID])
        var tags: [String: String] = [:]
        for tag in item.tags {
            let normalized = SearchNormalizer.normalize(tag)
            if !normalized.isEmpty, tags[normalized] == nil { tags[normalized] = tag }
        }
        for normalized in tags.keys.sorted() {
            let tagName = tags[normalized]!
            if let tagID = try String.fetchOne(
                db, sql: "SELECT id FROM tag WHERE normalizedName = ?", arguments: [normalized])
            {
                try db.execute(sql: "UPDATE tag SET name = ?, updatedAt = ? WHERE id = ?", arguments: [tagName, now, tagID])
                try db.execute(
                    sql: "INSERT INTO itemTag (itemID, tagID, createdAt) VALUES (?, ?, ?)",
                    arguments: [itemID, tagID, now])
            } else {
                let tagID = UUID().uuidString
                try db.execute(
                    sql: "INSERT INTO tag (id, name, normalizedName, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)",
                    arguments: [tagID, tagName, normalized, now, now])
                try db.execute(
                    sql: "INSERT INTO itemTag (itemID, tagID, createdAt) VALUES (?, ?, ?)",
                    arguments: [itemID, tagID, now])
            }
        }
    }

    private struct SearchCandidate {
        let summary: ItemSummary
        let normalizedName: String
        let normalizedAliases: [String]
        let normalizedTags: [String]
    }

    private static func fetchItems(
        _ db: Database,
        normalizedQuery: String,
        queryDidExecute: @Sendable (ReadQuery) -> Void
    ) throws -> [ItemSummary] {
        queryDidExecute(.items)
        let rows = try Row.fetchAll(db, sql: """
            SELECT item.*, scene.name AS sceneName, scene.imagePath AS sceneImagePath
            FROM item JOIN scene ON scene.id = item.sceneID
            """)

        queryDidExecute(.aliases)
        let aliasRows = try Row.fetchAll(db, sql: """
            SELECT itemID, value, normalizedValue
            FROM itemAlias
            ORDER BY itemID, normalizedValue
            """)
        var aliasesByItem: [String: [(value: String, normalized: String)]] = [:]
        for aliasRow in aliasRows {
            let itemID: String = aliasRow["itemID"]
            aliasesByItem[itemID, default: []].append((aliasRow["value"], aliasRow["normalizedValue"]))
        }

        queryDidExecute(.tags)
        let tagRows = try Row.fetchAll(db, sql: """
            SELECT itemTag.itemID, tag.name, tag.normalizedName
            FROM itemTag
            JOIN tag ON tag.id = itemTag.tagID
            ORDER BY itemTag.itemID, tag.normalizedName
            """)
        var tagsByItem: [String: [(name: String, normalized: String)]] = [:]
        for tagRow in tagRows {
            let itemID: String = tagRow["itemID"]
            tagsByItem[itemID, default: []].append((tagRow["name"], tagRow["normalizedName"]))
        }

        var candidates: [SearchCandidate] = []
        for row in rows {
            let itemID: String = row["id"]
            guard let id = UUID(uuidString: itemID),
                  let sceneID = UUID(uuidString: row["sceneID"] as String) else { continue }
            let aliases = aliasesByItem[itemID] ?? []
            let tags = tagsByItem[itemID] ?? []
            let name: String = row["name"]
            candidates.append(SearchCandidate(
                summary: ItemSummary(
                    id: id, sceneID: sceneID, sceneName: row["sceneName"], sceneImagePath: row["sceneImagePath"],
                    name: name, locationNote: row["locationNote"], note: row["note"],
                    normalizedX: row["normalizedX"], normalizedY: row["normalizedY"],
                    aliases: aliases.map(\.value), tags: tags.map(\.name),
                    appearanceOriginalImagePath: row["appearanceOriginalImagePath"],
                    appearanceCutoutImagePath: row["appearanceCutoutImagePath"],
                    createdAt: row["createdAt"], updatedAt: row["updatedAt"]),
                normalizedName: SearchNormalizer.normalize(name),
                normalizedAliases: aliases.map(\.normalized),
                normalizedTags: tags.map(\.normalized)))
        }
        return candidates.compactMap { candidate in
                rank(candidate, query: normalizedQuery).map { (candidate, $0) }
            }
            .sorted {
                if $0.1 != $1.1 { return $0.1 < $1.1 }
                if $0.0.summary.updatedAt != $1.0.summary.updatedAt {
                    return $0.0.summary.updatedAt > $1.0.summary.updatedAt
                }
                return $0.0.summary.id.uuidString < $1.0.summary.id.uuidString
            }
            .map { $0.0.summary }
    }

    private static func rank(_ candidate: SearchCandidate, query: String) -> Int? {
        if query.isEmpty || candidate.normalizedName.contains(query) { return 0 }
        if candidate.normalizedAliases.contains(where: { $0.contains(query) }) { return 1 }
        if candidate.normalizedTags.contains(where: { $0.contains(query) }) { return 2 }
        return nil
    }
}
