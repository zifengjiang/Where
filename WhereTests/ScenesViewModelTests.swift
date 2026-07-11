import Foundation
import Testing
@testable import Where

@MainActor
struct ScenesViewModelTests {
    @Test func emptyObservationFinishesLoading() async {
        let model = ScenesViewModel(repository: FakeSceneRepository(events: [.success([])]), imageStore: FakeSceneImageStore())
        model.start()
        await eventually { model.state == .loaded }
        #expect(model.scenes.isEmpty)
    }

    @Test func populatedObservationPreservesRepositoryOrderAndCounts() async {
        let newest = fixtureScene(name: "Newest", count: 4)
        let older = fixtureScene(name: "Older", count: 2)
        let model = ScenesViewModel(repository: FakeSceneRepository(events: [.success([newest, older])]), imageStore: FakeSceneImageStore())
        model.start()
        await eventually { model.scenes.count == 2 }
        #expect(model.scenes.map(\.name) == ["Newest", "Older"])
        #expect(model.scenes.map(\.itemCount) == [4, 2])
    }

    @Test func observationLoadsScenesAndSelection() async {
        let scene = fixtureScene(name: "Kitchen", count: 3)
        let repository = FakeSceneRepository(events: [.success([scene])])
        let model = ScenesViewModel(repository: repository, imageStore: FakeSceneImageStore())
        model.start()
        await eventually { model.scenes == [scene] }
        #expect(model.state == .loaded)
        model.select(scene)
        #expect(model.selectedSceneID == scene.id)
    }

    @Test func observationErrorCanRetry() async {
        let scene = fixtureScene(name: "Desk", count: 1)
        let repository = FakeSceneRepository(events: [.failure(TestError.failed), .success([scene])])
        let model = ScenesViewModel(repository: repository, imageStore: FakeSceneImageStore())
        model.start()
        await eventually { model.state == .failed }
        model.retry()
        await eventually { model.scenes == [scene] }
        #expect(repository.observeCount == 2)
    }

    @Test func deleteCommitsBeforeCleaningImages() async {
        let log = EventLog()
        let repository = FakeSceneRepository(events: [], log: log)
        let images = FakeSceneImageStore(log: log)
        let model = ScenesViewModel(repository: repository, imageStore: images)
        let scene = fixtureScene()
        model.requestDelete(scene)
        #expect(model.scenePendingDeletion == scene)
        await model.confirmDelete()
        #expect(log.values == ["database", "images"])
        #expect(model.scenePendingDeletion == nil)
    }

    @Test func databaseDeleteFailureNeverDeletesFiles() async {
        let repository = FakeSceneRepository(events: [], deleteError: TestError.failed)
        let images = FakeSceneImageStore()
        let model = ScenesViewModel(repository: repository, imageStore: images)
        model.requestDelete(fixtureScene())
        await model.confirmDelete()
        #expect(images.deleteCount == 0)
        #expect(model.deleteErrorMessage != nil)
    }

    @Test func cleanupFailureIsRecoverableAfterDatabaseDelete() async {
        let repository = FakeSceneRepository(events: [])
        let images = FakeSceneImageStore(error: TestError.failed)
        let model = ScenesViewModel(repository: repository, imageStore: images)
        model.requestDelete(fixtureScene())
        await model.confirmDelete()
        #expect(repository.deleteCount == 1)
        #expect(model.cleanupWarning != nil)
        images.error = nil
        await model.retryCleanup()
        #expect(repository.deleteCount == 1)
        #expect(images.deleteCount == 2)
        #expect(model.cleanupWarning == nil)
    }

    @Test func detailLoadsScenePinsAndTracksIntents() async {
        let scene = fixtureScene()
        let item = fixtureItem(scene: scene)
        let repository = FakeSceneRepository(events: [], detail: SceneDetail(scene: scene, items: [item]))
        let model = SceneDetailViewModel(sceneID: scene.id, repository: repository, imageStore: FakeSceneImageStore())
        model.start()
        await eventually { model.items == [item] }
        #expect(model.pins.map(\.id) == [item.id])
        model.selectPin(item.id)
        #expect(model.selectedItemID == item.id)
        model.requestEdit(); model.requestAddItem()
        #expect(model.isPresentingEdit && model.isPresentingAddItem)
    }
}

private enum TestError: Error { case failed }
private final class EventLog: @unchecked Sendable { var values: [String] = [] }

private final class FakeSceneRepository: SceneRepositoryProtocol, @unchecked Sendable {
    var events: [Result<[SceneSummary], Error>]
    var detail: SceneDetail?
    var deleteError: Error?
    var observeCount = 0
    var deleteCount = 0
    let log: EventLog?
    init(events: [Result<[SceneSummary], Error>], detail: SceneDetail? = nil, deleteError: Error? = nil, log: EventLog? = nil) {
        self.events = events; self.detail = detail; self.deleteError = deleteError; self.log = log
    }
    func observeScenes() -> AsyncThrowingStream<[SceneSummary], Error> {
        observeCount += 1
        let event = events.removeFirst()
        return AsyncThrowingStream { continuation in
            switch event { case .success(let value): continuation.yield(value); case .failure(let error): continuation.finish(throwing: error); return }
        }
    }
    func fetchScene(id: UUID) async throws -> SceneDetail { try #require(detail) }
    func deleteScene(id: UUID) async throws -> DeletedSceneImagePaths {
        deleteCount += 1; log?.values.append("database")
        if let deleteError { throw deleteError }
        return DeletedSceneImagePaths(scene: "Images/scene.jpg", items: [.init(original: "Images/a.jpg", cutout: nil)])
    }
}

private final class FakeSceneImageStore: SceneImageStoreProtocol, @unchecked Sendable {
    var error: Error?; var deleteCount = 0; let log: EventLog?
    init(error: Error? = nil, log: EventLog? = nil) { self.error = error; self.log = log }
    func loadImage(relativePath: String) async -> Data? { nil }
    func delete(relativePaths: [String]) async throws { deleteCount += 1; log?.values.append("images"); if let error { throw error } }
}

private func fixtureScene(name: String = "Room", count: Int = 1) -> SceneSummary {
    .init(id: UUID(), name: name, imagePath: "Images/scene.jpg", itemCount: count, createdAt: .now, updatedAt: .now)
}
private func fixtureItem(scene: SceneSummary) -> ItemSummary {
    .init(id: UUID(), sceneID: scene.id, sceneName: scene.name, sceneImagePath: scene.imagePath, name: "Keys", locationNote: "Shelf", note: nil, normalizedX: 0.2, normalizedY: 0.3, aliases: [], tags: [], appearanceOriginalImagePath: nil, appearanceCutoutImagePath: nil, createdAt: .now, updatedAt: .now)
}
@MainActor private func eventually(_ condition: @escaping () -> Bool) async {
    for _ in 0..<100 where !condition() { await Task.yield() }
}
