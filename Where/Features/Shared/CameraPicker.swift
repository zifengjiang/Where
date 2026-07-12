import AVFoundation
import SwiftUI
import UIKit

enum CameraAccessState: Equatable {
    case available
    case denied
    case unavailable
}

enum CameraPickerAction {
    case library
    var accessibilityLabel: String { "从相册选择" }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void
    var onChooseLibrary: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        if onChooseLibrary != nil {
            let libraryButton = UIButton(type: .system)
            var configuration = UIButton.Configuration.glass()
            configuration.title = "相册"
            configuration.image = UIImage(systemName: "photo.on.rectangle")
            configuration.imagePadding = 8
            libraryButton.configuration = configuration
            libraryButton.accessibilityLabel = CameraPickerAction.library.accessibilityLabel
            libraryButton.addTarget(context.coordinator, action: #selector(Coordinator.chooseLibrary), for: .touchUpInside)
            libraryButton.frame = CGRect(x: 24, y: 68, width: 104, height: 48)
            let overlay = UIView(frame: UIScreen.main.bounds)
            overlay.isUserInteractionEnabled = true
            overlay.addSubview(libraryButton)
            picker.cameraOverlayView = overlay
        }
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {
        context.coordinator.parent = self
    }

    static func requestAccess() async -> CameraAccessState {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .available
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video) ? .available : .denied
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                parent.onCancel()
                return
            }
            parent.onImage(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }

        @objc func chooseLibrary() { parent.onChooseLibrary?() }
    }
}

enum SystemSettings {
    @MainActor static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
