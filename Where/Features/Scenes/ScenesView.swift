import SwiftUI
import UIKit

enum SceneGridPolicy {
    static func columnCount(availableWidth: CGFloat, isAccessibilitySize: Bool) -> Int {
        guard !isAccessibilitySize else { return 1 }
        return availableWidth >= 360 ? 2 : 1
    }
    static func imageHeight(forCardWidth width: CGFloat) -> CGFloat { width * 0.75 }
}

struct ScenesView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            .toolbar { if model.cleanupWarning != nil { ToolbarItem(placement: .topBarTrailing) { Button("重试清理", systemImage: "arrow.clockwise") { Task { await model.retryCleanup() } } } } }
            .navigationDestination(for: UUID.self) { id in SceneDetailView(sceneID: id, repository: repository, imageStore: model.imageStore) }
        }
        .task { model.start() }
        .onDisappear { model.stop() }
        .alert("删除场景？", isPresented: Binding(get: { model.scenePendingDeletion != nil }, set: { if !$0 { model.cancelDelete() } })) {
            Button("取消", role: .cancel) { model.cancelDelete() }
            Button("删除", role: .destructive) { Task { await model.confirmDelete() } }
        } message: { Text("此场景及其中的所有物品都会被永久删除。") }
        .alert("图片清理未完成", isPresented: Binding(get: { model.cleanupWarning != nil }, set: { if !$0 { model.cleanupWarning = nil } })) {
            Button("重试") { Task { await model.retryCleanup() } }; Button("稍后", role: .cancel) {}
        } message: { Text(model.cleanupWarning ?? "") }
        .alert("无法删除场景", isPresented: Binding(get: { model.deleteErrorMessage != nil }, set: { if !$0 { model.cancelFailedDelete() } })) {
            Button("取消", role: .cancel) { model.cancelFailedDelete() }
            Button("重试") { Task { await model.retryDelete() } }
        } message: { Text(model.deleteErrorMessage ?? "") }
    }
    private var sceneGrid: some View {
        GeometryReader { proxy in
            let count = SceneGridPolicy.columnCount(availableWidth: proxy.size.width,
                                                    isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
            ScrollView { LazyVGrid(columns: columns, spacing: 20) {
                ForEach(model.scenes, id: \.id) { scene in
                    NavigationLink(value: scene.id) { SceneCard(scene: scene, imageStore: model.imageStore) }
                        .buttonStyle(.plain).contextMenu { Button("删除", systemImage: "trash", role: .destructive) { model.requestDelete(scene) } }
                        .accessibilityLabel("\(scene.name)，\(scene.itemCount) 件物品")
                        .accessibilityAction(named: "删除") { model.requestDelete(scene) }
                }
            }.padding(WhereTheme.pagePadding) }
        }
    }
}

private struct SceneCard: View {
    let scene: SceneSummary; let imageStore: any SceneImageStoreProtocol
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    var body: some View { VStack(alignment: .leading, spacing: 9) {
        GeometryReader { proxy in
            Group { if let image { Image(uiImage: image).resizable().scaledToFill().accessibilityLabel("\(scene.name)的场景照片") } else { ZStack { WhereTheme.orange.opacity(0.14); Image(systemName: "photo.badge.exclamationmark").font(.largeTitle).foregroundStyle(WhereTheme.ink.opacity(0.7)) }.accessibilityLabel("\(scene.name)的场景照片不可用") } }
                .frame(width: proxy.size.width, height: SceneGridPolicy.imageHeight(forCardWidth: proxy.size.width))
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    Text("\(scene.itemCount) 件物品").font(.caption.weight(.semibold))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule()).padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: WhereTheme.cardRadius))
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        Text(scene.name).font(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }.task(id: scene.imagePath) {
        guard let asset = await imageStore.loadImageAsset(relativePath: scene.imagePath) else { return }
        image = await SceneThumbnailCache.shared.thumbnail(path: scene.imagePath, asset: asset, maxPixelSize: Int(420 * displayScale))?.image
    } }
}
