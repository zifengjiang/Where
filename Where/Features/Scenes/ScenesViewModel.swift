import Foundation
import Observation

@MainActor @Observable
final class ScenesViewModel {
    enum LoadState: Equatable { case loading, loaded, failed }
    private let repository: any SceneRepositoryProtocol
    let imageStore: any SceneImageStoreProtocol
    private var observationTask: Task<Void, Never>?
    private var pendingCleanupPaths: [String] = []
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
            guard let self else { return }
            do { for try await scenes in repository.observeScenes() { self.scenes = scenes; self.state = .loaded } }
            catch { if !Task.isCancelled { self.state = .failed } }
        }
    }
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
            pendingCleanupPaths = [deleted.scene] + deleted.items.flatMap { [$0.original, $0.cutout].compactMap { $0 } }
            await retryCleanup()
        } catch { failedDeletionScene = scene; deleteErrorMessage = "无法删除场景，请重试。" }
    }
    func retryCleanup() async {
        guard !pendingCleanupPaths.isEmpty else { return }
        do { try await imageStore.delete(relativePaths: pendingCleanupPaths); pendingCleanupPaths = []; cleanupWarning = nil }
        catch { cleanupWarning = "场景已删除，但部分图片未能清理。你可以重试。" }
    }
}
