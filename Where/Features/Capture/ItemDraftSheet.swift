import PhotosUI
import SwiftUI
import UIKit

struct ItemDraftSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: SceneCaptureViewModel
    @State private var appearanceItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var sourceData: Data?
    @State private var isShowingSubjectPicker = false
    @State private var isLoadingPhoto = false
	@State private var isShowingAppearanceSources = false
	@State private var isShowingCamera = false
	@State private var isShowingCameraAlert = false
	@State private var cameraState: CameraAccessState = .available

    var body: some View {
        NavigationStack {
            Form {
                if let binding = pendingBinding {
                    Section("物品") {
                        TextField("名称（必填）", text: binding.name)
                        TextField("别名，用逗号分隔", text: binding.aliasesText, axis: .vertical)
                        TextField("标签，用逗号分隔", text: binding.tagsText, axis: .vertical)
                        TextField("位置说明", text: binding.locationNote, axis: .vertical)
                    }
                    Section("备忘") {
                        TextEditor(text: binding.note).frame(minHeight: 110)
                    }
                    Section("物品照片") {
                        if let preview = binding.wrappedValue.appearancePreview {
                            Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 220)
                                .accessibilityLabel("物品外观照片")
                        }
                        Button { isShowingAppearanceSources = true } label: {
                            Label(binding.wrappedValue.appearancePreview == nil ? "添加物品照片" : "更换物品照片", systemImage: "photo")
                        }
                        if isLoadingPhoto { ProgressView("正在读取照片…") }
						if let message = model.appearanceErrorMessage {
							Text(message).font(.callout).foregroundStyle(.red)
						}
                        Text("可选择照片中的主体，生成去背景的物品卡片。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let message = model.validationMessage {
                        Section { Text(message).foregroundStyle(.red) }
                    }
                }
            }
            .navigationTitle("记录物品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("取消") { model.dismissPendingItem(); dismiss() }.disabled(model.isProcessingImage)
				}
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { if model.commitPendingItem() { dismiss() } }.disabled(isLoadingPhoto)
                }
            }
        }
        .presentationDetents([.large])
        .onChange(of: appearanceItem) { _, item in load(item) }
		.confirmationDialog("选择物品照片", isPresented: $isShowingAppearanceSources, titleVisibility: .visible) {
			Button("拍照") { requestCamera() }
			PhotosPicker(selection: $appearanceItem, matching: .images) { Text("从相册选择") }
			Button("取消", role: .cancel) {}
		}
		.fullScreenCover(isPresented: $isShowingCamera) {
			CameraPicker { image in
				isShowingCamera = false
				Task {
					let data = await Task.detached(
						priority: .userInitiated,
						operation: { image.jpegData(compressionQuality: 0.92) }
					).value
					guard let data else {
						model.reportAppearanceError(ImageStoreError.encodingFailed, step: "编码")
						return
					}
					sourceData = data
					sourceImage = image
					isShowingSubjectPicker = true
				}
			} onCancel: { isShowingCamera = false }
			.ignoresSafeArea()
		}
		.alert("无法使用相机", isPresented: $isShowingCameraAlert) {
			if cameraState == .denied { Button("打开设置") { SystemSettings.openAppSettings() } }
			PhotosPicker(selection: $appearanceItem, matching: .images) { Text("改从相册选择") }
			Button("取消", role: .cancel) {}
		} message: {
			Text(cameraState == .unavailable ? "这台设备没有可用的相机。" : "请允许 Where 使用相机；照片只保存在此设备上。")
		}
        .fullScreenCover(isPresented: $isShowingSubjectPicker) {
            NavigationStack {
                if let sourceImage {
                    SubjectPickerView(sourceImage: sourceImage) { original in
                        saveAppearance(original: original, cutout: nil)
                    } onConfirmCutout: { cutout, _ in
                        saveAppearance(original: sourceImage, cutout: cutout.cgImage)
                    }
                    .navigationTitle("选择物品主体")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { isShowingSubjectPicker = false } } }
                }
            }
        }
    }

    private var pendingBinding: Binding<CaptureItemDraft>? {
        guard model.pendingItem != nil else { return nil }
        return Binding(
            get: { model.pendingItem! },
            set: { model.pendingItem = $0 }
        )
    }

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isLoadingPhoto = true
        Task {
            defer { isLoadingPhoto = false; appearanceItem = nil }
			do {
				guard let data = try await item.loadTransferable(type: Data.self) else { throw ImageStoreError.invalidImage }
				let image = await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value
				guard let image else { throw ImageStoreError.invalidImage }
				sourceData = data
				sourceImage = image
				isShowingSubjectPicker = true
			} catch {
				model.reportAppearanceError(error, step: "读取")
			}
        }
    }

	private func requestCamera() {
		Task {
			cameraState = await CameraPicker.requestAccess()
			if cameraState == .available { isShowingCamera = true } else { isShowingCameraAlert = true }
		}
	}

    private func saveAppearance(original: UIImage, cutout: CGImage?) {
		guard let data = sourceData ?? original.jpegData(compressionQuality: 0.92) else {
			model.reportAppearanceError(ImageStoreError.encodingFailed, step: "编码")
			return
		}
        isShowingSubjectPicker = false
        Task {
            isLoadingPhoto = true
            defer { isLoadingPhoto = false }
			do {
				try await model.setPendingAppearance(
					originalData: data,
					cutout: cutout,
					preview: cutout.map(UIImage.init(cgImage:)) ?? original
				)
			} catch {
				model.reportAppearanceError(error, step: "保存")
			}
        }
    }
}
