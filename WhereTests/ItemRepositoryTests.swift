import Foundation
import GRDB
import os
import Testing
@testable import Where

struct ItemRepositoryTests {
    @Test
    func fetchSceneIncludesCompleteAliasesAndTags() async throws {
        let (_, repository) = try makeRepository()
        try await repository.saveSceneDraft(sceneDraft(items: [itemDraft(name: "Cable", aliases: ["Charger"], tags: ["Travel"])]))
        let detail = try await repository.sceneRepository.fetchScene(id: sceneID)
        #expect(detail.items.first?.aliases == ["Charger"])
        #expect(detail.items.first?.tags == ["Travel"])
    }

    @Test
    func savesCompleteGraphAndDeduplicatesNormalizedAliasesAndTags() async throws {
        let (database, repository) = try makeRepository()
        let draft = sceneDraft(items: [
            itemDraft(
                name: "Cable",
                aliases: [" USB-C ", "ＵＳＢ－Ｃ", "charger"],
                tags: [" Tech ", "Ｔｅｃｈ", "Travel"]),
            itemDraft(id: item2ID, name: "Passport", aliases: ["ID"], tags: ["Travel"]),
        ])

        try await repository.saveSceneDraft(draft)

        let counts = try await database.writer.read { db in
            try ["scene", "item", "itemAlias", "tag", "itemTag"].map {
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($0)")!
            }
        }
        #expect(counts == [1, 2, 3, 2, 3])
    }

    @Test
    func searchMatchesNameAliasAndTagWithPrecedenceThenNewestFirst() async throws {
        let (database, repository) = try makeRepository()
        try await repository.saveSceneDraft(sceneDraft(items: [
            itemDraft(name: "Travel Cable"),
            itemDraft(id: item2ID, name: "Adapter", aliases: ["Travel plug"]),
            itemDraft(id: item3ID, name: "Passport", tags: ["Travel"]),
            itemDraft(id: item4ID, name: "Travel Case"),
        ]))
        let newest = Date(timeIntervalSince1970: 2_000)
        let older = Date(timeIntervalSince1970: 1_000)
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE item SET updatedAt = ? WHERE id = ?", arguments: [older, item1ID.uuidString])
            try db.execute(sql: "UPDATE item SET updatedAt = ? WHERE id = ?", arguments: [newest, item4ID.uuidString])
        }

        let results = try await repository.searchItems(query: "  ＴＲＡＶＥＬ ")

        #expect(results.map(\.id) == [item4ID, item1ID, item2ID, item3ID])
    }

    @Test
    func blankQueryReturnsAllNewestFirst() async throws {
        let (database, repository) = try makeRepository()
        try await repository.saveSceneDraft(sceneDraft(items: [
            itemDraft(name: "Older"),
            itemDraft(id: item2ID, name: "Newer"),
        ]))
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE item SET updatedAt = ? WHERE id = ?", arguments: [Date(timeIntervalSince1970: 1), item1ID.uuidString])
            try db.execute(sql: "UPDATE item SET updatedAt = ? WHERE id = ?", arguments: [Date(timeIntervalSince1970: 2), item2ID.uuidString])
        }

        #expect(try await repository.searchItems(query: " \n ").map(\.id) == [item2ID, item1ID])
    }

    @Test(arguments: ["%", "_", "'", "\""])
    func searchTreatsSqlMetacharactersAsData(query: String) async throws {
        let (_, repository) = try makeRepository()
        try await repository.saveSceneDraft(sceneDraft(items: [
            itemDraft(name: "contains \(query) literally"),
            itemDraft(id: item2ID, name: "ordinary"),
        ]))

        #expect(try await repository.searchItems(query: query).map(\.id) == [item1ID])
    }

    @Test
    func updatesPreserveCreatedAtAndReplaceChildren() async throws {
        let (database, repository) = try makeRepository()
        try await repository.saveSceneDraft(sceneDraft(items: [itemDraft(name: "Cable", aliases: ["old"], tags: ["old"])]))
        let original: (Date, Date) = try await database.writer.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT createdAt, updatedAt FROM item WHERE id = ?", arguments: [item1ID.uuidString])!
            return (row["createdAt"], row["updatedAt"])
        }
        try await Task.sleep(for: .milliseconds(10))

        try await repository.saveSceneDraft(sceneDraft(name: "Updated Room", items: [itemDraft(name: "Updated Cable", aliases: ["new"], tags: ["new"])]))

        let updated: (Date, Date) = try await database.writer.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT createdAt, updatedAt FROM item WHERE id = ?", arguments: [item1ID.uuidString])!
            return (row["createdAt"], row["updatedAt"])
        }
        #expect(updated.0 == original.0)
        #expect(updated.1 > original.1)
        #expect(try await repository.searchItems(query: "old").isEmpty)
        #expect(try await repository.searchItems(query: "new").map(\.id) == [item1ID])
    }

    @Test
    func validationFailureRollsBackCompleteGraph() async throws {
        let (database, repository) = try makeRepository()
        let invalid = itemDraft(id: item2ID, name: "Invalid", normalizedX: 2)

        await #expect(throws: Error.self) {
            try await repository.saveSceneDraft(sceneDraft(items: [itemDraft(name: "Valid"), invalid]))
        }
        let counts = try await database.writer.read { db in
            try ["scene", "item", "tag"].map {
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($0)")!
            }
        }
        #expect(counts == [0, 0, 0])
    }

    @Test
    func deleteItemReturnsPathsAndRemovesOnlyUnusedTags() async throws {
        let (database, repository) = try makeRepository()
        try await repository.saveSceneDraft(sceneDraft(items: [
            itemDraft(name: "Cable", tags: ["Shared", "Unused"], originalPath: "original/cable.jpg", cutoutPath: "cutout/cable.png"),
            itemDraft(id: item2ID, name: "Adapter", tags: ["Shared"]),
        ]))

        let paths = try await repository.deleteItem(id: item1ID)

        #expect(paths == DeletedImagePaths(original: "original/cable.jpg", cutout: "cutout/cable.png"))
        let remainingTags = try await database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT normalizedName FROM tag ORDER BY normalizedName")
        }
        #expect(remainingTags == ["shared"])
    }

    @Test
    func itemAndSceneObservationsEmitUpdates() async throws {
        let (_, repository) = try makeRepository()
        let sceneRepository = repository.sceneRepository
        var itemValues = repository.observeItems(query: "cable").makeAsyncIterator()
        var sceneValues = sceneRepository.observeScenes().makeAsyncIterator()
        #expect(try await itemValues.next() == [])
        #expect(try await sceneValues.next() == [])

        try await repository.saveSceneDraft(sceneDraft(items: [itemDraft(name: "Cable")]))

        #expect(try await itemValues.next()?.map(\.id) == [item1ID])
        #expect(try await sceneValues.next()?.map(\.id) == [sceneID])
    }

    @Test
    func deleteSceneReturnsSceneAndItemImagePaths() async throws {
        let (database, repository) = try makeRepository()
        try await repository.saveSceneDraft(sceneDraft(items: [
            itemDraft(name: "Cable", tags: ["Travel"], originalPath: "original/cable.jpg", cutoutPath: "cutout/cable.png"),
        ]))

        let paths = try await repository.sceneRepository.deleteScene(id: sceneID)

        #expect(paths == DeletedSceneImagePaths(
            scene: "scenes/travel.jpg",
            items: [DeletedImagePaths(original: "original/cable.jpg", cutout: "cutout/cable.png")]))
        let counts = try await database.writer.read { db in
            try ["scene", "item", "itemAlias", "itemTag", "tag"].map {
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($0)")!
            }
        }
        #expect(counts == [0, 0, 0, 0, 0])
    }

    @Test
    func searchBulkLoadsRelatedDataWithBoundedQueryCount() async throws {
        let database = try AppDatabase.inMemory()
        let queryPhases = OSAllocatedUnfairLock(initialState: [ItemRepository.ReadQuery]())
        let repository = ItemRepository(database: database) { query in
            queryPhases.withLock { $0.append(query) }
        }
        try await repository.saveSceneDraft(sceneDraft(items: [
            itemDraft(name: "One", aliases: ["first"], tags: ["group"]),
            itemDraft(id: item2ID, name: "Two", aliases: ["second"], tags: ["group"]),
            itemDraft(id: item3ID, name: "Three", aliases: ["third"], tags: ["group"]),
            itemDraft(id: item4ID, name: "Four", aliases: ["fourth"], tags: ["group"]),
        ]))

        _ = try await repository.searchItems(query: "group")

        #expect(queryPhases.withLock { $0 } == [.items, .aliases, .tags])
    }

    @Test
    func sceneObservationThrowsForMalformedSceneIdentifier() async throws {
        let database = try AppDatabase.inMemory()
        let repository = SceneRepository(database: database)
        try await database.writer.write { db in
            try db.execute(
                sql: "INSERT INTO scene (id, name, imagePath, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)",
                arguments: ["not-a-uuid", "Broken", "broken.jpg", Date(), Date()])
        }
        var iterator = repository.observeScenes().makeAsyncIterator()

        await #expect(throws: RepositoryError.self) {
            _ = try await iterator.next()
        }
    }

    @Test
    func sceneDeletionReturnsItemPathsInIdentifierOrder() async throws {
        let (_, repository) = try makeRepository()
        try await repository.saveSceneDraft(sceneDraft(items: [
            itemDraft(id: item2ID, name: "Second", originalPath: "second.jpg"),
            itemDraft(name: "First", originalPath: "first.jpg"),
        ]))

        let result = try await repository.sceneRepository.deleteScene(id: sceneID)

        #expect(result.items.map(\.original) == ["first.jpg", "second.jpg"])
    }

    @Test
    func cancellingItemObservationFinishesConsumer() async throws {
        let (_, repository) = try makeRepository()
        let task = Task {
            for try await _ in repository.observeItems(query: "") {}
        }
        await Task.yield()

        task.cancel()

        try await task.value
        #expect(task.isCancelled)
    }

    private func makeRepository() throws -> (AppDatabase, ItemRepository) {
        let database = try AppDatabase.inMemory()
        return (database, ItemRepository(database: database))
    }

    private func sceneDraft(name: String = "Travel Bag", items: [ItemDraft]) -> SceneDraft {
        SceneDraft(id: sceneID, name: name, imagePath: "scenes/travel.jpg", items: items)
    }

    private func itemDraft(
        id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
        name: String,
        aliases: [String] = [],
        tags: [String] = [],
        normalizedX: Double = 0.25,
        originalPath: String? = nil,
        cutoutPath: String? = nil
    ) -> ItemDraft {
        ItemDraft(
            id: id, name: name, locationNote: "Front pocket", note: "Keep dry",
            normalizedX: normalizedX, normalizedY: 0.75, aliases: aliases, tags: tags,
            appearanceOriginalImagePath: originalPath, appearanceCutoutImagePath: cutoutPath)
    }

    private var sceneID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000001")! }
    private var item1ID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000011")! }
    private var item2ID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000012")! }
    private var item3ID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000013")! }
    private var item4ID: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000014")! }
}
