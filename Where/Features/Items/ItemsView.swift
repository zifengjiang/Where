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

struct ItemAppearanceLoadPlan: Equatable {
    struct Candidate: Equatable {
        enum Source: Equatable { case cutout, original }
        let source: Source
        let path: String
    }
    let candidates: [Candidate]

    init(cutout: String?, original: String?) {
        var values: [Candidate] = []
        if let cutout, !cutout.isEmpty { values.append(.init(source: .cutout, path: cutout)) }
        if let original, !original.isEmpty { values.append(.init(source: .original, path: original)) }
        candidates = values
    }
}

@MainActor
enum ItemAppearanceCandidateLoader {
    struct Loaded<Value> { let candidate: ItemAppearanceLoadPlan.Candidate; let value: Value }
    static func firstAvailable<Value>(
        in plan: ItemAppearanceLoadPlan,
        load: (ItemAppearanceLoadPlan.Candidate) async -> Value?
    ) async -> Loaded<Value>? {
        for candidate in plan.candidates {
            guard !Task.isCancelled else { return nil }
            if let value = await load(candidate) { return Loaded(candidate: candidate, value: value) }
        }
        return nil
    }
}

struct ItemAppearanceText: Equatable {
    let note: String
    let createdAt: String
    init(item: ItemSummary) {
        note = item.note ?? ""
        createdAt = ItemCardState.createdAtText(item.createdAt)
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
                else if model.state == .loaded && model.items.isEmpty && !model.hasEffectiveQuery { emptyState }
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
                if let item = model.selectedItem {
                    let plan = ItemAppearanceLoadPlan(cutout: item.appearanceCutoutImagePath,
                                                      original: item.appearanceOriginalImagePath)
                    AppearanceCard(item: item, imageStore: imageStore)
                        .frame(maxWidth: .infinity)
                        .frame(height: plan.candidates.isEmpty ? 92 : 240)
                        .transition(.opacity)
                }
                if model.state == .loading {
                    ProgressView("正在搜索…").padding(.vertical, 8)
                }
                if model.items.isEmpty && model.hasEffectiveQuery {
                    ContentUnavailableView(
                        "没有找到“\(model.effectiveQuery)”",
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
            .background(WhereTheme.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
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
            ItemRowThumbnail(item: item, imageStore: imageStore)
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
                .foregroundStyle(selected ? WhereTheme.pin : Color.secondary)
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(selected ? WhereTheme.pin.opacity(0.11) : Color.secondary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .leading) {
            if selected { Capsule().fill(WhereTheme.pin).frame(width: 3).padding(.vertical, 10) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name)，位于 \(item.sceneName)\(selected ? "，已选择" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ItemRowThumbnail: View {
    let item: ItemSummary
    let imageStore: any SceneImageStoreProtocol
    @State private var image: UIImage?

    private var plan: ItemAppearanceLoadPlan {
        ItemAppearanceLoadPlan(cutout: item.appearanceCutoutImagePath,
                               original: item.appearanceOriginalImagePath)
    }

    var body: some View {
        ZStack {
            Color.orange.opacity(0.12)
            if let image { Image(uiImage: image).resizable().scaledToFit().padding(4) }
            else { Image(systemName: "shippingbox").foregroundStyle(.secondary) }
        }
        .accessibilityLabel(image == nil ? "\(item.name)的物品照片不可用" : "\(item.name)的物品照片")
        .task(id: plan) {
            image = nil
            let loaded: ItemAppearanceCandidateLoader.Loaded<UIImage>? = await ItemAppearanceCandidateLoader.firstAvailable(in: plan) { candidate in
                guard let asset = await imageStore.loadImageAsset(relativePath: candidate.path) else { return nil }
                return await SceneThumbnailCache.shared.thumbnail(
                    path: candidate.path, asset: asset, maxPixelSize: 160
                )?.image
            }
            guard !Task.isCancelled else { return }
            image = loaded?.value
        }
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
    let imageStore: any SceneImageStoreProtocol
    @State private var loadedImage: UIImage?
    @State private var loadedSource: ItemAppearanceLoadPlan.Candidate.Source?
    @State private var imageRevision = ""
    @State private var isLoading = true
    @State private var retryToken = 0

    private var plan: ItemAppearanceLoadPlan {
        ItemAppearanceLoadPlan(cutout: item.appearanceCutoutImagePath,
                               original: item.appearanceOriginalImagePath)
    }
    private var text: ItemAppearanceText { ItemAppearanceText(item: item) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !plan.candidates.isEmpty {
                Group {
                    if let loadedImage, let loadedSource {
                        switch loadedSource {
                        case .cutout:
                            ItemCardView(item: item, cutoutImage: loadedImage, imageRevision: imageRevision)
                                .padding(.horizontal, 16)
                        case .original:
                            Image(uiImage: loadedImage).resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    } else if isLoading {
                        ZStack { Color.orange.opacity(0.08); ProgressView("正在载入物品照片…") }
                    } else {
                        ZStack {
                            Color.orange.opacity(0.08)
                            VStack(spacing: 6) {
                                Image(systemName: "photo.badge.exclamationmark")
                                Text("物品照片不可用").font(.subheadline)
                                Button("重试") { retryToken += 1 }.font(.caption)
                            }.foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if !text.note.isEmpty { Text(text.note).font(.subheadline).lineLimit(2) }
            Text(text.createdAt).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
        .task(id: AppearanceLoadIdentity(plan: plan, retryToken: retryToken)) { await loadAppearance() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.name)。备忘：\(text.note.isEmpty ? "无" : text.note)。\(text.createdAt)")
    }

    private func loadAppearance() async {
        loadedImage = nil; loadedSource = nil; isLoading = !plan.candidates.isEmpty
        let loaded: ItemAppearanceCandidateLoader.Loaded<(SceneThumbnail, UInt64)>? = await ItemAppearanceCandidateLoader.firstAvailable(in: plan) { candidate in
            guard let asset = await imageStore.loadImageAsset(relativePath: candidate.path),
                  let thumbnail = await SceneThumbnailCache.shared.thumbnail(
                    path: candidate.path, asset: asset, maxPixelSize: 1000
                  ) else { return nil }
            return (thumbnail, asset.revision)
        }
        guard !Task.isCancelled else { return }
        if let loaded {
            loadedImage = loaded.value.0.image
            loadedSource = loaded.candidate.source
            imageRevision = "\(loaded.candidate.path)-\(loaded.value.1)"
            isLoading = false
            return
        }
        isLoading = false
    }

    private struct AppearanceLoadIdentity: Equatable {
        let plan: ItemAppearanceLoadPlan
        let retryToken: Int
    }
}

#if DEBUG
private enum ItemsPreviewState { case empty, loading, error, content, selected }
private struct ItemsStatePreview: View {
    let state: ItemsPreviewState
    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .empty: ContentUnavailableView("还没有物品", systemImage: "shippingbox", description: Text("在场景照片上添加定位点后，它们会出现在这里。"))
                case .loading: ProgressView("正在载入物品…")
                case .error: VStack { ContentUnavailableView("无法载入物品", systemImage: "exclamationmark.triangle"); Button("重试") {}.buttonStyle(.glassProminent) }
                case .content, .selected:
                    ScrollView { VStack(spacing: 16) {
                        if state == .selected {
                            ZStack { RoundedRectangle(cornerRadius: 20).fill(WhereTheme.orange.opacity(0.16)).aspectRatio(16/10, contentMode: .fit); VStack { Image(systemName: "location.circle.fill").font(.largeTitle).foregroundStyle(WhereTheme.pin); Text("备用钥匙位于玄关").font(.headline) } }
                        } else { ContentUnavailableView("选择一个物品查看它的位置", systemImage: "location.magnifyingglass").frame(height: 148) }
                        ForEach(["备用钥匙", "充电线", "旅行药包"], id: \.self) { name in
                            HStack { RoundedRectangle(cornerRadius: 12).fill(WhereTheme.orange.opacity(0.15)).frame(width: 48, height: 48).overlay { Image(systemName: "shippingbox") }; VStack(alignment: .leading) { Text(name).font(.headline); Text("玄关 · 常用").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: state == .selected && name == "备用钥匙" ? "checkmark.circle.fill" : "location.fill").foregroundStyle(state == .selected && name == "备用钥匙" ? WhereTheme.pin : .secondary) }.padding(12).background(WhereTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }.padding() }
                }
            }.navigationTitle("所有物品").background(WhereTheme.canvas)
        }
    }
}
#Preview("Items · Empty · Light") { ItemsStatePreview(state: .empty) }
#Preview("Items · Loading · Dark") { ItemsStatePreview(state: .loading).preferredColorScheme(.dark) }
#Preview("Items · Error · AX") { ItemsStatePreview(state: .error).environment(\.dynamicTypeSize, .accessibility2) }
#Preview("Items · Content") { ItemsStatePreview(state: .content) }
#Preview("Items · Selected Inline Location · Dark") { ItemsStatePreview(state: .selected).preferredColorScheme(.dark) }
#endif
