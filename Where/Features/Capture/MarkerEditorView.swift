import SwiftUI

struct MarkerEditorView: View {
    @Bindable var model: SceneCaptureViewModel
    let onFinish: () -> Void
    @State private var selectedItemID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if let image = model.sceneImage {
                GeometryReader { proxy in
                    let geometry = AspectFitGeometry(imageSize: image.size, containerSize: proxy.size)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable().scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .accessibilityLabel("\(model.sceneName)的场景照片")
                        ForEach(model.items) { item in
                            marker(item, geometry: geometry)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { point in
                        if model.beginItem(at: point, in: proxy.size) { selectedItemID = nil }
                    }
                }
            }

            HStack {
                Text(model.items.isEmpty ? "点击照片添加第一个物品" : "已标记 \(model.items.count) 件物品")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("完成") { onFinish() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isSaving)
            }
            .padding()
            .background(.bar)
        }
        .overlay { if model.isSaving { ProgressView("正在保存…").padding().glassEffect() } }
        .safeAreaInset(edge: .top) {
            if let message = model.saveErrorMessage {
                Text(message).font(.callout).foregroundStyle(.red).padding(10).frame(maxWidth: .infinity).background(.bar)
            }
        }
        .sheet(isPresented: Binding(
            get: { model.pendingItem != nil },
            set: { if !$0 { model.dismissPendingItem() } }
        )) {
            ItemDraftSheet(model: model)
                .presentationDetents([.medium, .large])
                .interactiveDismissDisabled(model.isProcessingImage)
        }
    }

    private func marker(_ item: CaptureItemDraft, geometry: AspectFitGeometry) -> some View {
        let selected = selectedItemID == item.id
        return Button {
            selectedItemID = item.id
            model.editItem(id: item.id)
        } label: {
            ZStack {
                Circle().fill(.tint).frame(width: selected ? 30 : 24, height: selected ? 30 : 24)
                Circle().stroke(.white, lineWidth: selected ? 3 : 2).frame(width: selected ? 30 : 24, height: selected ? 30 : 24)
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
		.contextMenu {
			Button("删除", role: .destructive) { model.removeItem(id: item.id) }
		}
        .position(geometry.viewPoint(for: item.normalizedPoint))
        .gesture(
            DragGesture(minimumDistance: 4).onChanged { value in
                guard let point = geometry.normalizedPoint(for: value.location) else { return }
                selectedItemID = item.id
                model.moveItem(id: item.id, to: point)
            }
        )
        .accessibilityLabel(item.name)
        .accessibilityHint("轻点编辑，拖动可调整位置，长按可删除")
        .accessibilityAddTraits(selected ? .isSelected : [])
		.accessibilityAction(named: "删除") { model.removeItem(id: item.id) }
    }
}
