import PhotosUI
import SwiftUI
import UIKit

enum CaptureCanvasPolicy {
    static let backgroundAssetName = "WhereCanvas"
    static let fieldSurfaceAssetName = "WhereSurface"
}

enum CaptureInitialDestination: Equatable { case camera, photos, permissionRecovery }
enum CaptureInitialSource {
    static func destination(for state: CameraAccessState) -> CaptureInitialDestination {
        switch state { case .available: .camera; case .unavailable: .photos; case .denied: .permissionRecovery }
    }
}
enum CapturePresentationPolicy {
    static func showsForm(hasSceneImage: Bool) -> Bool { hasSceneImage }
}

struct SceneDraftView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: SceneCaptureViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var isShowingPhotoLibrary = false
    @State private var isShowingCamera = false
    @State private var isShowingCameraAlert = false
    @State private var cameraState: CameraAccessState = .available
    @State private var didPresentInitialSource = false

    init(repository: any ItemRepositoryProtocol, imageStore: ImageStore) {
        _model = State(initialValue: SceneCaptureViewModel(repository: repository, imageStore: imageStore))
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                switch model.step {
                case .source, .details:
                    if CapturePresentationPolicy.showsForm(hasSceneImage: model.sceneImage != nil) {
                        sceneDetails
                    } else {
                        ProgressView("正在打开照片来源…")
                            .accessibilityIdentifier("capture-source-loading")
                    }
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
        .task { await presentInitialSourceIfNeeded() }
        .photosPicker(isPresented: $isShowingPhotoLibrary, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in load(item) }
        .onChange(of: isShowingPhotoLibrary) { _, isPresented in
            if !isPresented { handlePhotoLibraryDismissal() }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in
                isShowingCamera = false
                load(image)
            } onCancel: {
                isShowingCamera = false
                if model.sceneImage == nil { cancelInitialAcquisition() }
            } onChooseLibrary: {
                isShowingCamera = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    isShowingPhotoLibrary = true
                }
            }
            .ignoresSafeArea()
        }
        .alert("无法使用相机", isPresented: $isShowingCameraAlert) {
            if cameraState == .denied { Button("打开设置") { SystemSettings.openAppSettings() } }
            Button("改从相册选择") { isShowingPhotoLibrary = true }
            Button("取消", role: .cancel) {}
        } message: {
            Text(cameraState == .unavailable ? "这台设备没有可用的相机。" : "请允许 Where 使用相机。照片只用于记录家中物品，并保存在此设备上。")
        }
    }

    private var sceneDetails: some View {
        @Bindable var model = model
        return ScrollView {
            VStack(spacing: 20) {
                Button { requestCamera() } label: {
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
                Button("从相册选择") { isShowingPhotoLibrary = true }
                    .buttonStyle(.glass).frame(minHeight: 44)

                VStack(alignment: .leading, spacing: 8) {
                    Text("场景名称").font(.headline)
                    TextField("", text: $model.sceneName, prompt: Text("例如：玄关").foregroundStyle(WhereTheme.ink.opacity(0.68)))
                        .padding(.horizontal, 12).padding(.vertical, 11)
                        .foregroundStyle(WhereTheme.ink).tint(WhereTheme.pin)
                        .background(WhereTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).stroke(WhereTheme.ink.opacity(0.35)) }
                        .textContentType(.location).submitLabel(.next)
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
            switch CaptureInitialSource.destination(for: cameraState) {
            case .camera: isShowingCamera = true
            case .photos: isShowingPhotoLibrary = true
            case .permissionRecovery: isShowingCameraAlert = true
            }
        }
    }

    private func presentInitialSourceIfNeeded() async {
        guard !didPresentInitialSource else { return }
        didPresentInitialSource = true
        cameraState = await CameraPicker.requestAccess()
        switch CaptureInitialSource.destination(for: cameraState) {
        case .camera: isShowingCamera = true
        case .photos: isShowingPhotoLibrary = true
        case .permissionRecovery: isShowingCameraAlert = true
        }
    }

    private func handlePhotoLibraryDismissal() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard model.sceneImage == nil, photoItem == nil, !model.isProcessingImage else { return }
            await cancelInitialAcquisitionAndWait()
        }
    }

    private func cancelInitialAcquisition() {
        Task { await cancelInitialAcquisitionAndWait() }
    }

    private func cancelInitialAcquisitionAndWait() async {
        guard model.sceneImage == nil else { return }
        if await model.cancel() { dismiss() }
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

#if DEBUG
private struct CaptureFormPreview: View {
    @State private var name = ""
    let hasPhoto: Bool
    var body: some View {
        NavigationStack {
            ScrollView { VStack(spacing: 20) {
                ZStack { RoundedRectangle(cornerRadius: 20).fill(WhereTheme.surface).aspectRatio(4/3, contentMode: .fit); VStack { Image(systemName: hasPhoto ? "photo.fill" : "camera").font(.largeTitle).foregroundStyle(.secondary); Text(hasPhoto ? "玄关照片" : "添加场景照片").font(.headline); Text(hasPhoto ? "轻点更换" : "拍照或从相册选择").foregroundStyle(.secondary) } }
                VStack(alignment: .leading, spacing: 8) { Text("场景名称").font(.headline); TextField("", text: $name, prompt: Text("例如：玄关").foregroundStyle(WhereTheme.ink.opacity(0.68))).foregroundStyle(WhereTheme.ink).padding(12).background(WhereTheme.surface, in: RoundedRectangle(cornerRadius: 10)).overlay { RoundedRectangle(cornerRadius: 10).stroke(WhereTheme.ink.opacity(0.35)) } }
            }.padding() }.safeAreaInset(edge: .bottom) { Button { } label: { Text("下一步：标记物品").frame(maxWidth: .infinity) }.buttonStyle(.glassProminent).controlSize(.large).padding().background(WhereTheme.canvas) }.navigationTitle("添加场景").background(WhereTheme.canvas)
        }
    }
}
#Preview("Capture · Empty Form · Light") { CaptureFormPreview(hasPhoto: false) }
#Preview("Capture · Photo Selected · Dark") { CaptureFormPreview(hasPhoto: true).preferredColorScheme(.dark) }
#Preview("Capture · Form · AX") { CaptureFormPreview(hasPhoto: false).environment(\.dynamicTypeSize, .accessibility2) }
#endif
