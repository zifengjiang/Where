import Foundation
import GRDB

protocol SceneRepositoryProtocol: Sendable {
    func observeScenes() -> AsyncThrowingStream<[SceneSummary], Error>
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
