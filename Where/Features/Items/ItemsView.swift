import SwiftUI
import UIKit

enum ItemAppearanceSource: Equatable {
    case cutout(String)
    case original(String)

    var path: String {
        switch self { case .cutout(let path), .original(let path): path }
    }

    static func resolve(cutout: String?, original: String?) -> ItemAppearanceSource? {
        if let cutout, !cutout.isEmpty { return .cutout(cutout) }
        if let original, !original.isEmpty { return .original(original) }
        return nil
    }
}

struct ItemsView: View {
    @Environment(\.displayScale) private var displayScale
    @State private var model: ItemsViewModel
    private let imageStore: any SceneImageStoreProtocol

    init(repository: any ItemRepositoryProtocol, imageStore: any SceneImageStoreProtocol) {
        _model = State(initialValue: ItemsViewModel(repository: repository))
        self.imageStore = imageStore
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if model.state == .failed { errorState }
                else if model.state == .loaded && model.items.isEmpty && model.query.isEmpty { emptyState }
                else { content }
            }
            .navigationTitle("所有物品")
            .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "搜索名称、别名或标签")
        }
        .task { model.start() }
        .onDisappear { model.stop() }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                locationHeader
                if let item = model.selectedItem,
                   let source = ItemAppearanceSource.resolve(
                    cutout: item.appearanceCutoutImagePath,
                    original: item.appearanceOriginalImagePath
                   ) {
                    AppearanceCard(item: item, source: source, imageStore: imageStore)
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .transition(.opacity)
                }
                if model.state == .loading {
                    ProgressView("正在搜索…").padding(.vertical, 8)
                }
                if model.items.isEmpty && !model.query.isEmpty {
                    ContentUnavailableView(
                        "没有找到“\(model.query)”",
                        systemImage: "magnifyingglass",
                        description: Text("请尝试物品的别名或标签。")
                    )
                    .padding(.top, 24)
                } else {
                    ForEach(model.items, id: \.id) { item in
                        Button { withAnimation(.snappy(duration: 0.22)) { model.select(item) } } label: {
                            ItemRow(item: item, selected: model.selectedItem?.id == item.id, imageStore: imageStore)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("在页面顶部显示物品位置")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder private var locationHeader: some View {
        if let item = model.selectedItem {
            VStack(alignment: .leading, spacing: 10) {
                AsyncImageFileView(
                    relativePath: item.sceneImagePath,
                    imageStore: imageStore,
                    maxPixelSize: Int(1400 * displayScale),
                    accessibilityLabel: locationAccessibilityLabel(item),
                    failureStyle: .location
                ) { image in
                    ScenePhotoView(
                        image: image,
                        pins: [ScenePin(id: item.id, name: item.name, locationNote: item.locationNote,
                                        normalizedPoint: CGPoint(x: item.normalizedX, y: item.normalizedY))],
                        selectedItemID: item.id,
                        imageAccessibilityLabel: locationAccessibilityLabel(item)
                    )
                    .background(.black)
                }
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .id(item.id)
                .transition(.opacity)

                Text(item.name).font(.headline)
                Label(locationText(item), systemImage: "location.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)
        } else {
            ContentUnavailableView(
                "选择一个物品查看它的位置",
                systemImage: "location.magnifyingglass",
                description: Text("点按下方物品后，场景照片会显示在这里。")
            )
            .frame(maxWidth: .infinity, minHeight: 148)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var emptyState: some View {
        ContentUnavailableView("还没有物品", systemImage: "shippingbox",
                               description: Text("在场景照片上添加定位点后，它们会出现在这里。"))
    }

    private var errorState: some View {
        VStack(spacing: 16) {
            ContentUnavailableView("无法载入物品", systemImage: "exclamationmark.triangle",
                                   description: Text("物品仍保存在设备上，请重试。"))
            Button("重试", action: model.retry).buttonStyle(.borderedProminent)
        }
    }

    private func locationText(_ item: ItemSummary) -> String {
        [item.sceneName, item.locationNote].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
    }

    private func locationAccessibilityLabel(_ item: ItemSummary) -> String {
        let detail = item.locationNote.map { "。\($0)" } ?? ""
        return "\(item.name) 位于 \(item.sceneName)\(detail)"
    }
}

private struct ItemRow: View {
    let item: ItemSummary
    let selected: Bool
    let imageStore: any SceneImageStoreProtocol

    var body: some View {
        HStack(spacing: 12) {
            AsyncImageFileView(relativePath: item.appearanceCutoutImagePath ?? item.appearanceOriginalImagePath,
                               imageStore: imageStore, maxPixelSize: 160,
                               accessibilityLabel: "\(item.name)的物品照片",
                               failurePolicy: .compact) { image in
                Image(uiImage: image).resizable().scaledToFit().padding(4)
            }
            .frame(width: 48, height: 48)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(.headline).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.tags.isEmpty { TagSummary(tags: item.tags) }
                Text(item.sceneName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: selected ? "checkmark.circle.fill" : "location.fill")
                .foregroundStyle(selected ? Color.red : Color.secondary)
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(selected ? Color.red.opacity(0.10) : Color.secondary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .leading) {
            if selected { Capsule().fill(Color.red).frame(width: 3).padding(.vertical, 10) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name)，位于 \(item.sceneName)\(selected ? "，已选择" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct TagSummary: View {
    let tags: [String]
    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(tags.prefix(2).enumerated()), id: \.offset) { _, tag in
                Text(tag).font(.caption.weight(.medium)).lineLimit(1)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.orange.opacity(0.14), in: Capsule())
            }
            if tags.count > 2 { Text("+\(tags.count - 2)").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct AppearanceCard: View {
    let item: ItemSummary
    let source: ItemAppearanceSource
    let imageStore: any SceneImageStoreProtocol

    var body: some View {
        AsyncImageFileView(relativePath: source.path,
                           imageStore: imageStore, maxPixelSize: 1000,
                           accessibilityLabel: "\(item.name)的物品卡片") { image in
            switch source {
            case .cutout:
                ItemCardView(item: item, cutoutImage: image, imageRevision: source.path)
                    .padding(.horizontal, 16)
            case .original:
                OriginalAppearanceCard(item: item, image: image)
            }
        }
    }
}

private struct OriginalAppearanceCard: View {
    let item: ItemSummary
    let image: UIImage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 170)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            if let note = item.note, !note.isEmpty {
                Text(note).font(.subheadline).lineLimit(2)
            }
            Text(ItemCardState.createdAtText(item.createdAt))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name)。备忘：\(item.note ?? "无")。\(ItemCardState.createdAtText(item.createdAt))")
    }
}
