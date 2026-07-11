import SwiftUI
import UIKit

struct ScenesView: View {
    @State private var model: ScenesViewModel
    private let repository: any SceneRepositoryProtocol
    init(repository: any SceneRepositoryProtocol, imageStore: any SceneImageStoreProtocol) {
        self.repository = repository
        _model = State(initialValue: ScenesViewModel(repository: repository, imageStore: imageStore))
    }
    var body: some View {
        NavigationStack {
            Group {
                if model.state == .loading { ProgressView("正在载入场景…") }
                else if model.state == .failed { VStack(spacing: 16) { ContentUnavailableView("无法载入场景", systemImage: "exclamationmark.triangle", description: Text("请检查后重试。")); Button("重试", action: model.retry).buttonStyle(.borderedProminent) } }
                else if model.scenes.isEmpty { ContentUnavailableView("还没有场景", systemImage: "photo.on.rectangle", description: Text("添加一个场景，开始记录物品的位置。")) }
                else { sceneGrid }
            }
            .navigationTitle("场景")
            .navigationDestination(for: UUID.self) { id in SceneDetailView(sceneID: id, repository: repository, imageStore: model.imageStore) }
        }
        .task { model.start() }
        .alert("删除场景？", isPresented: Binding(get: { model.scenePendingDeletion != nil }, set: { if !$0 { model.cancelDelete() } })) {
            Button("取消", role: .cancel) { model.cancelDelete() }
            Button("删除", role: .destructive) { Task { await model.confirmDelete() } }
        } message: { Text("此场景及其中的所有物品都会被永久删除。") }
        .alert("图片清理未完成", isPresented: Binding(get: { model.cleanupWarning != nil }, set: { if !$0 { model.cleanupWarning = nil } })) {
            Button("重试") { Task { await model.retryCleanup() } }; Button("稍后", role: .cancel) {}
        } message: { Text(model.cleanupWarning ?? "") }
    }
    private var sceneGrid: some View {
        ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
            ForEach(model.scenes, id: \.id) { scene in
                NavigationLink(value: scene.id) { SceneCard(scene: scene, imageStore: model.imageStore) }
                    .buttonStyle(.plain).contextMenu { Button("删除", systemImage: "trash", role: .destructive) { model.requestDelete(scene) } }
                    .accessibilityLabel("\(scene.name)，\(scene.itemCount) 件物品")
            }
        }.padding() }
    }
}

private struct SceneCard: View {
    let scene: SceneSummary; let imageStore: any SceneImageStoreProtocol
    @State private var image: UIImage?
    var body: some View { VStack(alignment: .leading, spacing: 10) {
        Group { if let image { Image(uiImage: image).resizable().scaledToFill() } else { ZStack { Color.orange.opacity(0.12); Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary) } } }
            .frame(height: 130).clipShape(RoundedRectangle(cornerRadius: 18))
        Text(scene.name).font(.headline).lineLimit(1)
        Text("\(scene.itemCount) 件物品").font(.subheadline).foregroundStyle(.secondary)
    }.task(id: scene.imagePath) { if let data = await imageStore.loadImage(relativePath: scene.imagePath) { image = UIImage(data: data) } } }
}
