import SwiftUI
import UIKit

struct SceneDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: SceneDetailViewModel
    @State private var image: UIImage?
    @State private var confirmsDelete = false
    init(sceneID: UUID, repository: any SceneRepositoryProtocol, imageStore: any SceneImageStoreProtocol) {
        _model = State(initialValue: SceneDetailViewModel(sceneID: sceneID, repository: repository, imageStore: imageStore))
    }
    var body: some View {
        Group {
            if model.isLoading { ProgressView("正在载入场景…") }
            else if let error = model.errorMessage { VStack(spacing: 16) { ContentUnavailableView("无法载入场景", systemImage: "exclamationmark.triangle", description: Text(error)); Button("重试") { Task { await model.load() } }.buttonStyle(.borderedProminent) } }
            else { detail }
        }
        .navigationTitle(model.scene?.name ?? "场景")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Menu {
            Button("删除场景", systemImage: "trash", role: .destructive) { confirmsDelete = true }
        } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("场景操作") } }
        .task { model.start() }
        .alert("删除场景？", isPresented: $confirmsDelete) { Button("取消", role: .cancel) {}; Button("删除", role: .destructive) { Task { if await model.deleteScene() == .deleted { dismiss() } } } } message: { Text("此场景及其中的所有物品都会被永久删除。") }
        .alert("无法删除", isPresented: Binding(get: { model.deleteErrorMessage != nil }, set: { if !$0 { model.deleteErrorMessage = nil } })) { Button("取消", role: .cancel) {}; Button("重试") { Task { if await model.deleteScene() == .deleted { dismiss() } } } } message: { Text(model.deleteErrorMessage ?? "") }
        .alert("图片清理未完成", isPresented: Binding(get: { model.cleanupWarning != nil }, set: { _ in })) {
            Button("继续") { dismiss() }
            Button("重试") { Task { if await model.retryDeleteCleanup() { dismiss() } } }
        } message: { Text(model.cleanupWarning ?? "") }
    }
    @ViewBuilder private var detail: some View {
        if let image {
            VStack(spacing: 0) {
                ScenePhotoView(image: image, pins: model.pins, selectedItemID: model.selectedItemID,
                               imageAccessibilityLabel: "\(model.scene?.name ?? "场景")的场景照片", onPinTap: model.selectPin)
                    .background(.black)
                if let selected = model.items.first(where: { $0.id == model.selectedItemID }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selected.name).font(.headline)
                        if let note = selected.locationNote, !note.isEmpty {
                            Label(note, systemImage: "location.fill").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(WhereTheme.surface)
                }
            }
        }
        else { ContentUnavailableView("照片不可用", systemImage: "photo.badge.exclamationmark", description: Text(model.scene?.name ?? "场景信息仍可查看。"))
            .task(id: model.scene?.imagePath) { if let path = model.scene?.imagePath, let asset = await model.imageStore.loadImageAsset(relativePath: path) { image = await SceneThumbnailCache.shared.thumbnail(path: path, asset: asset, maxPixelSize: Int(1536 * UIScreen.main.scale))?.image } } }
    }
}
