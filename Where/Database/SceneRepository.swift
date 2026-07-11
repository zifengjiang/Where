import Foundation
import GRDB

protocol SceneRepositoryProtocol: Sendable {
    func observeScenes() -> AsyncThrowingStream<[SceneSummary], Error>
    func fetchScene(id: UUID) async throws -> SceneDetail
    func deleteScene(id: UUID) async throws -> DeletedSceneImagePaths
}

final class SceneRepository: SceneRepositoryProtocol, Sendable {
    private let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    func observeScenes() -> AsyncThrowingStream<[SceneSummary], Error> {
        let writer = database.writer
        let observation = ValueObservation.tracking { db in
            try Self.fetchScenes(db)
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

    func deleteScene(id: UUID) async throws -> DeletedSceneImagePaths {
        try await database.writer.write { db in
            guard let scenePath = try String.fetchOne(
                db, sql: "SELECT imagePath FROM scene WHERE id = ?", arguments: [id.uuidString]
            ) else {
                throw RepositoryError.notFound
            }
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT appearanceOriginalImagePath, appearanceCutoutImagePath
                    FROM item WHERE sceneID = ? ORDER BY id
                    """,
                arguments: [id.uuidString])
            let itemPaths = rows.map {
                DeletedImagePaths(original: $0["appearanceOriginalImagePath"], cutout: $0["appearanceCutoutImagePath"])
            }
            try db.execute(sql: "DELETE FROM scene WHERE id = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM tag WHERE NOT EXISTS (SELECT 1 FROM itemTag WHERE itemTag.tagID = tag.id)")
            return DeletedSceneImagePaths(scene: scenePath, items: itemPaths)
        }
    }

    func fetchScene(id: UUID) async throws -> SceneDetail {
        try await database.writer.read { db in
            guard let sceneRow = try Row.fetchOne(db, sql: """
                SELECT scene.*, COUNT(item.id) AS itemCount FROM scene
                LEFT JOIN item ON item.sceneID = scene.id WHERE scene.id = ? GROUP BY scene.id
                """, arguments: [id.uuidString]) else { throw RepositoryError.notFound }
            let rawID: String = sceneRow["id"]
            guard let sceneID = UUID(uuidString: rawID) else { throw RepositoryError.invalidIdentifier(rawID) }
            let scene = SceneSummary(id: sceneID, name: sceneRow["name"], imagePath: sceneRow["imagePath"], itemCount: sceneRow["itemCount"], createdAt: sceneRow["createdAt"], updatedAt: sceneRow["updatedAt"])
            let itemRows = try Row.fetchAll(db, sql: "SELECT * FROM item WHERE sceneID = ? ORDER BY updatedAt DESC, id ASC", arguments: [id.uuidString])
            let aliasRows = try Row.fetchAll(db, sql: """
                SELECT itemAlias.itemID, itemAlias.value FROM itemAlias
                JOIN item ON item.id = itemAlias.itemID WHERE item.sceneID = ?
                ORDER BY itemAlias.itemID, itemAlias.normalizedValue
                """, arguments: [id.uuidString])
            let tagRows = try Row.fetchAll(db, sql: """
                SELECT itemTag.itemID, tag.name FROM itemTag
                JOIN item ON item.id = itemTag.itemID JOIN tag ON tag.id = itemTag.tagID
                WHERE item.sceneID = ? ORDER BY itemTag.itemID, tag.normalizedName
                """, arguments: [id.uuidString])
            var aliases: [String: [String]] = [:]
            for row in aliasRows { aliases[row["itemID"], default: []].append(row["value"]) }
            var tags: [String: [String]] = [:]
            for row in tagRows { tags[row["itemID"], default: []].append(row["name"]) }
            let items = try itemRows.map { row in
                let rawItemID: String = row["id"]
                guard let itemID = UUID(uuidString: rawItemID) else { throw RepositoryError.invalidIdentifier(rawItemID) }
                return ItemSummary(id: itemID, sceneID: sceneID, sceneName: scene.name, sceneImagePath: scene.imagePath, name: row["name"], locationNote: row["locationNote"], note: row["note"], normalizedX: row["normalizedX"], normalizedY: row["normalizedY"], aliases: aliases[rawItemID] ?? [], tags: tags[rawItemID] ?? [], appearanceOriginalImagePath: row["appearanceOriginalImagePath"], appearanceCutoutImagePath: row["appearanceCutoutImagePath"], createdAt: row["createdAt"], updatedAt: row["updatedAt"])
            }
            return SceneDetail(scene: scene, items: items)
        }
    }

    private static func fetchScenes(_ db: Database) throws -> [SceneSummary] {
        try Row.fetchAll(db, sql: """
            SELECT scene.id, scene.name, scene.imagePath, scene.createdAt, scene.updatedAt,
                   COUNT(item.id) AS itemCount
            FROM scene
            LEFT JOIN item ON item.sceneID = scene.id
            GROUP BY scene.id
            ORDER BY scene.updatedAt DESC, scene.id ASC
            """).map { row in
                let rawID: String = row["id"]
                guard let id = UUID(uuidString: rawID) else {
                    throw RepositoryError.invalidIdentifier(rawID)
                }
                return SceneSummary(
                    id: id, name: row["name"], imagePath: row["imagePath"], itemCount: row["itemCount"],
                    createdAt: row["createdAt"], updatedAt: row["updatedAt"])
            }
    }
}

enum RepositoryError: Error, Equatable {
    case notFound
    case invalidIdentifier(String)
}
