import Foundation
import Observation

@MainActor @Observable
final class SceneDetailViewModel {
    let sceneID: UUID
    private let repository: any SceneRepositoryProtocol
    let imageStore: any SceneImageStoreProtocol
    var scene: SceneSummary?
    var items: [ItemSummary] = []
    var selectedItemID: UUID?
    var isLoading = true
    var errorMessage: String?
    var isPresentingEdit = false
    var isPresentingAddItem = false
    var deleteErrorMessage: String?
    var cleanupWarning: String?
    init(sceneID: UUID, repository: any SceneRepositoryProtocol, imageStore: any SceneImageStoreProtocol) { self.sceneID = sceneID; self.repository = repository; self.imageStore = imageStore }
    var pins: [ScenePin] { items.map { ScenePin(id: $0.id, name: $0.name, locationNote: $0.locationNote, normalizedPoint: .init(x: $0.normalizedX, y: $0.normalizedY)) } }
    func start() { Task { await load() } }
    func load() async { isLoading = true; do { let detail = try await repository.fetchScene(id: sceneID); scene = detail.scene; items = detail.items; errorMessage = nil } catch { errorMessage = "无法载入场景，请重试。" }; isLoading = false }
    func selectPin(_ id: UUID) { selectedItemID = id }
    func requestEdit() { isPresentingEdit = true }
    func requestAddItem() { isPresentingAddItem = true }
    func deleteScene() async -> Bool {
        do {
            let deleted = try await repository.deleteScene(id: sceneID)
            let paths = [deleted.scene] + deleted.items.flatMap { [$0.original, $0.cutout].compactMap { $0 } }
            do { try await imageStore.delete(relativePaths: paths) }
            catch { cleanupWarning = "场景已删除，但部分图片未能清理。" }
            return true
        } catch {
            deleteErrorMessage = "无法删除场景，请重试。"
            return false
        }
    }
}
