import Foundation
import Testing
import UIKit
@testable import Where

@MainActor
struct ScenesViewModelTests {
    @Test func thumbnailCacheHitsBySizeAndMissesForDifferentSize() async {
        let counter = DecodeCounter()
        let cache = SceneThumbnailCache(maximumCost: 10_000) { _, _ in counter.count += 1; return SceneThumbnail(image: UIImage(), decodedByteCost: 1) }
        let asset = SceneImageAsset(data: Data([1]), revision: 1)
        _ = await cache.thumbnail(path: "a", asset: asset, maxPixelSize: 100)
        _ = await cache.thumbnail(path: "a", asset: asset, maxPixelSize: 100)
        _ = await cache.thumbnail(path: "a", asset: asset, maxPixelSize: 200)
        #expect(counter.count == 2)
    }

    @Test func thumbnailCacheEvictsByDecodedByteCost() async {
        let counter = DecodeCounter()
        let cache = SceneThumbnailCache(maximumCost: 10) { _, _ in counter.count += 1; return SceneThumbnail(image: UIImage(), decodedByteCost: 6) }
        let asset = SceneImageAsset(data: Data([1]), revision: 1)
        _ = await cache.thumbnail(path: "a", asset: asset, maxPixelSize: 100)
        _ = await cache.thumbnail(path: "b", asset: asset, maxPixelSize: 100)
        _ = await cache.thumbnail(path: "a", asset: asset, maxPixelSize: 100)
        #expect(counter.count == 3)
    }
    @Test func observationTaskDoesNotRetainModel() async {
        let repository = HangingSceneRepository()
        weak var weakModel: ScenesViewModel?
        do {
            let model = ScenesViewModel(repository: repository, imageStore: FakeSceneImageStore())
            weakModel = model
            model.start()
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(weakModel == nil)
    }
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
        let scene = fixtureScene()
        model.requestDelete(scene)
        await model.confirmDelete()
        #expect(images.deleteCount == 0)
        #expect(model.deleteErrorMessage != nil)
        #expect(model.failedDeletionScene?.id == scene.id)
    }

    @Test func listDeleteFailureCanRetryTheStoredTarget() async {
        let repository = FakeSceneRepository(events: [], deleteError: TestError.failed)
        let model = ScenesViewModel(repository: repository, imageStore: FakeSceneImageStore())
        let scene = fixtureScene()
        model.requestDelete(scene)
        await model.confirmDelete()
        repository.deleteError = nil
        await model.retryDelete()
        #expect(repository.deleteCount == 2)
        #expect(model.failedDeletionScene == nil)
        #expect(model.deleteErrorMessage == nil)
    }

    @Test func cleanupFailureIsRecoverableAfterDatabaseDelete() async {
        let repository = FakeSceneRepository(events: [])
        let images = FakeSceneImageStore(error: TestError.failed)
        let model = ScenesViewModel(repository: repository, imageStore: images)
        model.requestDelete(fixtureScene())
        await model.confirmDelete()
        #expect(repository.deleteCount == 1)
        #expect(model.cleanupWarning != nil)
        #expect(await images.hasPendingCleanup())
        images.error = nil
        await model.retryCleanup()
        #expect(repository.deleteCount == 1)
        #expect(images.deleteCount == 2)
        #expect(model.cleanupWarning == nil)
    }

    @Test func enqueueFailureRetriesPathsWithoutRepeatingDatabaseDelete() async {
        let repository = FakeSceneRepository(events: [])
        let images = FakeSceneImageStore(enqueueError: TestError.failed)
        let model = ScenesViewModel(repository: repository, imageStore: images)
        model.requestDelete(fixtureScene())
        await model.confirmDelete()
        #expect(repository.deleteCount == 1)
        images.enqueueError = nil
        await model.retryCleanup()
        #expect(repository.deleteCount == 1)
        #expect(images.enqueueCount == 2)
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

    @Test func detailDatabaseDeleteFailureStaysOnScreen() async {
        let scene = fixtureScene()
        let repository = FakeSceneRepository(events: [], detail: SceneDetail(scene: scene, items: []), deleteError: TestError.failed)
        let model = SceneDetailViewModel(sceneID: scene.id, repository: repository, imageStore: FakeSceneImageStore())
        #expect(await model.deleteScene() == .failed)
        #expect(model.deleteErrorMessage != nil)
    }

    @Test func detailCleanupFailureDoesNotDismissAndRetryNeverDeletesDatabaseTwice() async {
        let scene = fixtureScene()
        let repository = FakeSceneRepository(events: [], detail: SceneDetail(scene: scene, items: []))
        let images = FakeSceneImageStore(error: TestError.failed)
        let model = SceneDetailViewModel(sceneID: scene.id, repository: repository, imageStore: images)
        #expect(await model.deleteScene() == .cleanupPending)
        #expect(repository.deleteCount == 1)
        images.error = nil
        #expect(await model.retryDeleteCleanup() == true)
        #expect(repository.deleteCount == 1)
        #expect(images.deleteCount == 2)
    }

    @Test func detailEnqueueFailureRetriesWithoutRepeatingDatabaseDelete() async {
        let scene = fixtureScene()
        let repository = FakeSceneRepository(events: [], detail: SceneDetail(scene: scene, items: []))
        let images = FakeSceneImageStore(enqueueError: TestError.failed)
        let model = SceneDetailViewModel(sceneID: scene.id, repository: repository, imageStore: images)
        #expect(await model.deleteScene() == .cleanupPending)
        images.enqueueError = nil
        #expect(await model.retryDeleteCleanup())
        #expect(repository.deleteCount == 1)
        #expect(images.enqueueCount == 2)
    }

    @Test func dismissedDetailTransfersFailedEnqueueToAppScopedStore() async {
        let scene = fixtureScene()
        let repository = FakeSceneRepository(events: [], detail: SceneDetail(scene: scene, items: []))
        let images = FakeSceneImageStore(enqueueError: TestError.failed)
        var detail: SceneDetailViewModel? = SceneDetailViewModel(sceneID: scene.id, repository: repository, imageStore: images)
        #expect(await detail?.deleteScene() == .cleanupPending)
        detail = nil
        #expect(await images.hasPendingCleanup())
        images.enqueueError = nil
        let scenes = ScenesViewModel(repository: FakeSceneRepository(events: []), imageStore: images)
        await scenes.retryCleanup()
        #expect(images.pendingPaths.isEmpty)
        #expect(repository.deleteCount == 1)
    }
}

private final class HangingSceneRepository: SceneRepositoryProtocol, @unchecked Sendable {
    func observeScenes() -> AsyncThrowingStream<[SceneSummary], Error> { AsyncThrowingStream { _ in } }
    func fetchScene(id: UUID) async throws -> SceneDetail { throw TestError.failed }
    func deleteScene(id: UUID) async throws -> DeletedSceneImagePaths { throw TestError.failed }
}

private enum TestError: Error { case failed }
private final class DecodeCounter: @unchecked Sendable { var count = 0 }
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
    var error: Error?; var enqueueError: Error?; var deleteCount = 0; var enqueueCount = 0; let log: EventLog?; var pendingPaths: [String] = []
    init(error: Error? = nil, enqueueError: Error? = nil, log: EventLog? = nil) { self.error = error; self.enqueueError = enqueueError; self.log = log }
    func loadImage(relativePath: String) async -> Data? { nil }
    func delete(relativePaths: [String]) async throws { deleteCount += 1; log?.values.append("images"); if let error { throw error } }
    func enqueueCleanup(relativePaths: [String]) async throws { enqueueCount += 1; pendingPaths.append(contentsOf: relativePaths); if let enqueueError { throw enqueueError } }
    func hasPendingCleanup() async -> Bool { !pendingPaths.isEmpty }
    func retryPendingCleanup() async throws { try await delete(relativePaths: pendingPaths); pendingPaths = [] }
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
