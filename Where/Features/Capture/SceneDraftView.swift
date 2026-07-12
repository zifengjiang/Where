import PhotosUI
import SwiftUI
import UIKit

enum CaptureCanvasPolicy {
    static let backgroundAssetName = "WhereCanvas"
}

struct SceneDraftView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: SceneCaptureViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var isShowingSourceChoices = true
    @State private var isShowingCamera = false
    @State private var isShowingCameraAlert = false
    @State private var cameraState: CameraAccessState = .available

    init(repository: any ItemRepositoryProtocol, imageStore: ImageStore) {
        _model = State(initialValue: SceneCaptureViewModel(repository: repository, imageStore: imageStore))
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                switch model.step {
                case .source, .details: sceneDetails
                case .markers:
                    MarkerEditorView(model: model) {
                        Task {
                            await model.finish()
                            if model.didFinish { dismiss() }
                        }
                    }
                }
            }
            .background(WhereTheme.canvas.ignoresSafeArea())
            .navigationTitle(model.step == .markers ? "标记物品" : "添加场景")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { cancelButton }
            }
        }
		.interactiveDismissDisabled(model.isSaving || model.hasCommittedGraphPendingCompensation)
        .background(WhereTheme.canvas.ignoresSafeArea())
        .confirmationDialog("选择场景照片", isPresented: $isShowingSourceChoices, titleVisibility: .visible) {
            Button("拍照") { requestCamera() }
            PhotosPicker(selection: $photoItem, matching: .images) { Text("从相册选择") }
            Button("取消", role: .cancel) {}
        }
        .onChange(of: photoItem) { _, item in load(item) }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in
                isShowingCamera = false
                load(image)
            } onCancel: { isShowingCamera = false }
            .ignoresSafeArea()
        }
        .alert("无法使用相机", isPresented: $isShowingCameraAlert) {
            if cameraState == .denied { Button("打开设置") { SystemSettings.openAppSettings() } }
            PhotosPicker(selection: $photoItem, matching: .images) { Text("改从相册选择") }
            Button("取消", role: .cancel) {}
        } message: {
            Text(cameraState == .unavailable ? "这台设备没有可用的相机。" : "请允许 Where 使用相机。照片只用于记录家中物品，并保存在此设备上。")
        }
    }

    private var sceneDetails: some View {
        @Bindable var model = model
        return ScrollView {
            VStack(spacing: 20) {
                Button { isShowingSourceChoices = true } label: {
                    ZStack(alignment: .bottomTrailing) {
                        if let image = model.sceneImage {
                            Image(uiImage: image).resizable().scaledToFit()
                            Label("更换", systemImage: "arrow.triangle.2.circlepath")
                                .font(.callout.weight(.semibold)).padding(10)
                                .glassEffect(.regular.interactive(), in: .capsule).padding(12)
                        } else {
                            ContentUnavailableView("添加场景照片", systemImage: "camera", description: Text("拍照或从相册选择"))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.sceneImage == nil ? "选择场景照片" : "更换场景照片")

                VStack(alignment: .leading, spacing: 8) {
                    Text("场景名称").font(.headline)
                    TextField("例如：玄关", text: $model.sceneName)
                        .textFieldStyle(.roundedBorder).textContentType(.location).submitLabel(.next)
                        .onSubmit { _ = model.beginMarking() }
                }.frame(maxWidth: .infinity, alignment: .leading)

                if let message = model.validationMessage ?? model.imageErrorMessage {
                    Text(message).font(.callout).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                }

            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            Button { _ = model.beginMarking() } label: {
                Text("下一步：标记物品").frame(maxWidth: .infinity)
            }
                .buttonStyle(.glassProminent).controlSize(.large)
                .disabled(model.sceneImage == nil || model.isProcessingImage).padding()
                .background(WhereTheme.canvas)
        }
        .background(WhereTheme.canvas.ignoresSafeArea())
        .overlay { if model.isProcessingImage { WhereGlassHUD { ProgressView("正在处理照片…") } } }
    }

    private var cancelButton: some View {
        Button("取消") {
			Task {
				if await model.cancel() { dismiss() }
			}
        }
        .disabled(model.isSaving)
    }

    private func requestCamera() {
        Task {
            cameraState = await CameraPicker.requestAccess()
            if cameraState == .available { isShowingCamera = true } else { isShowingCameraAlert = true }
        }
    }

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw ImageStoreError.invalidImage }
                try await model.setSceneImage(data: data)
            } catch { model.reportImageError(error) }
            photoItem = nil
        }
    }

    private func load(_ image: UIImage) {
        Task {
			let data = await Task.detached(priority: .userInitiated) { image.jpegData(compressionQuality: 0.92) }.value
			guard let data else { return }
            do { try await model.setSceneImage(data: data, pixelSize: image.size) }
            catch { model.reportImageError(error) }
        }
    }
}
