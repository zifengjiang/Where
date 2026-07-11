import Foundation
import Observation

@MainActor @Observable
final class ScenesViewModel {
    enum LoadState: Equatable { case loading, loaded, failed }
    private let repository: any SceneRepositoryProtocol
    let imageStore: any SceneImageStoreProtocol
    private var observationTask: Task<Void, Never>?
    var scenes: [SceneSummary] = []
    var state: LoadState = .loading
    var selectedSceneID: UUID?
    var scenePendingDeletion: SceneSummary?
    var failedDeletionScene: SceneSummary?
    var deleteErrorMessage: String?
    var cleanupWarning: String?

    init(repository: any SceneRepositoryProtocol, imageStore: any SceneImageStoreProtocol) { self.repository = repository; self.imageStore = imageStore }
    func start() {
        observationTask?.cancel(); state = .loading
        observationTask = Task { [weak self] in
            guard let repository = self?.repository else { return }
            do { for try await scenes in repository.observeScenes() { guard !Task.isCancelled else { return }; self?.scenes = scenes; self?.state = .loaded } }
            catch { if !Task.isCancelled { self?.state = .failed } }
        }
        Task { [weak self] in await self?.refreshCleanupState() }
    }
    func stop() { observationTask?.cancel(); observationTask = nil }
    func retry() { start() }
    func select(_ scene: SceneSummary) { selectedSceneID = scene.id }
    func requestDelete(_ scene: SceneSummary) { scenePendingDeletion = scene; failedDeletionScene = nil; deleteErrorMessage = nil }
    func cancelDelete() { scenePendingDeletion = nil }
    func confirmDelete() async {
        guard let scene = scenePendingDeletion else { return }
        scenePendingDeletion = nil
        await delete(scene)
    }
    func retryDelete() async {
        guard let scene = failedDeletionScene else { return }
        deleteErrorMessage = nil
        await delete(scene)
    }
    func cancelFailedDelete() { failedDeletionScene = nil; deleteErrorMessage = nil }
    private func delete(_ scene: SceneSummary) async {
        do {
            let deleted = try await repository.deleteScene(id: scene.id)
            failedDeletionScene = nil
            let paths = [deleted.scene] + deleted.items.flatMap { [$0.original, $0.cutout].compactMap { $0 } }
            do { try await imageStore.enqueueCleanup(relativePaths: paths); await retryCleanup() }
            catch { cleanupWarning = "场景已删除，但图片清理任务未能保存。" }
        } catch { failedDeletionScene = scene; deleteErrorMessage = "无法删除场景，请重试。" }
    }
    func retryCleanup() async {
        guard await imageStore.hasPendingCleanup() else { cleanupWarning = nil; return }
        do { try await imageStore.retryPendingCleanup(); cleanupWarning = nil }
        catch { cleanupWarning = "场景已删除，但部分图片未能清理。你可以重试。" }
    }
    func refreshCleanupState() async { if await imageStore.hasPendingCleanup() { cleanupWarning = "有图片等待清理。你可以重试。" } }
}
