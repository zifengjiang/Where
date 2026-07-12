import AVFoundation
import Observation
import PhotosUI
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

/// Kept for the existing overlay hit-test regression tests. The new camera
/// surface does not use a full-screen overlay; its controls are native SwiftUI
/// views layered over the preview instead.
final class CameraPassthroughOverlayView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// A small AVFoundation camera surface following the ShipSwift camera recipe:
/// the session starts as soon as the view appears and PhotosPicker stays inside
/// the camera surface, so the capture flow never needs an outer loading screen.
struct CameraPicker: View {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void
    var onChooseLibrary: (() -> Void)? = nil

    @Environment(\.scenePhase) private var scenePhase
    @State private var manager = SWCameraManager()
    @State private var isShowingLibrary = false
    @State private var libraryItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch manager.state {
            case .authorized:
                cameraSurface
            case .denied:
                accessRecovery("需要相机权限", message: "允许 Where 使用相机，或从相册选择照片。", settings: true)
            case .unavailable:
                accessRecovery("相机不可用", message: "这台设备没有可用的相机，请从相册选择照片。", settings: false)
            case .checking:
                Color.black.ignoresSafeArea()
                    .overlay { ProgressView("准备相机…").tint(.white).foregroundStyle(.white) }
            }
        }
        .task { await manager.prepare() }
        .onDisappear { manager.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await manager.refreshAuthorization() } }
        }
        .photosPicker(isPresented: $isShowingLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    onImage(image)
                } catch {
                    libraryItem = nil
                }
            }
        }
    }

    private var cameraSurface: some View {
        ZStack {
            SWCameraPreview(session: manager.session)
                .ignoresSafeArea()
                .accessibilityLabel("相机取景")

            VStack {
                HStack(spacing: 12) {
                    Button { onCancel() } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.48), in: Circle())
                    }
                    .accessibilityLabel("取消拍摄")
                    Spacer()
                    Button { chooseLibrary() } label: {
                        Label("相册", systemImage: "photo.on.rectangle")
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(.black.opacity(0.48), in: Capsule())
                    }
                    .accessibilityLabel(CameraPickerAction.library.accessibilityLabel)
                    .accessibilityHint("从相册选择照片")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.top, 12)

                Spacer()

                HStack(spacing: 44) {
                    Button { manager.switchCamera() } label: {
                        Image(systemName: "camera.rotate")
                            .font(.title3)
                            .frame(width: 48, height: 48)
                            .background(.black.opacity(0.48), in: Circle())
                    }
                    .accessibilityLabel("切换摄像头")

                    Button { manager.capturePhoto { onImage($0) } } label: {
                        Circle()
                            .fill(.white)
                            .frame(width: 76, height: 76)
                            .overlay { Circle().stroke(.black.opacity(0.25), lineWidth: 2).padding(5) }
                    }
                    .disabled(manager.isCapturing)
                    .accessibilityLabel("拍照")

                    Button { manager.toggleFlash() } label: {
                        Image(systemName: manager.flashEnabled ? "bolt.fill" : "bolt.slash")
                            .font(.title3)
                            .frame(width: 48, height: 48)
                            .background(.black.opacity(0.48), in: Circle())
                    }
                    .accessibilityLabel(manager.flashEnabled ? "关闭闪光灯" : "打开闪光灯")
                }
                .foregroundStyle(.white)
                .padding(.bottom, 34)
            }
        }
    }

    private func chooseLibrary() {
        if let onChooseLibrary { onChooseLibrary() }
        else { isShowingLibrary = true }
    }

    private func accessRecovery(_ title: String, message: String, settings: Bool) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.fill").font(.system(size: 42)).foregroundStyle(.white.opacity(0.8))
            Text(title).font(.title2.weight(.semibold)).foregroundStyle(.white)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.72)).padding(.horizontal, 24)
            if settings {
                Button("打开设置") { SystemSettings.openAppSettings() }.buttonStyle(.borderedProminent)
            }
            Button("从相册选择") { isShowingLibrary = true }.buttonStyle(.bordered).tint(.white)
            Button("取消", role: .cancel) { onCancel() }.foregroundStyle(.white)
        }
        .padding()
    }

    static func requestAccess() async -> CameraAccessState {
        await SWCameraManager.requestAccess()
    }
}

@Observable
final class SWCameraManager: NSObject, @unchecked Sendable, AVCapturePhotoCaptureDelegate {
    enum State: Equatable { case checking, authorized, denied, unavailable }

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.where.camera.session", qos: .userInitiated)
    private var captureCompletion: ((UIImage) -> Void)?
    private var currentDevice: AVCaptureDevice?
    private(set) var state: State = .checking
    private(set) var isCapturing = false
    var flashEnabled = false

    func prepare() async {
        await refreshAuthorization()
    }

    func refreshAuthorization() async {
        let access = await Self.requestAccess()
        guard access == .available else {
            await MainActor.run { self.state = access == .denied ? .denied : .unavailable }
            return
        }
        await MainActor.run { self.state = .authorized }
        configureIfNeeded()
    }

    static func requestAccess() async -> CameraAccessState {
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            return .unavailable
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .available
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video) ? .available : .denied
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    private func configureIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.inputs.isEmpty else {
                self?.start()
                return
            }
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  self.session.canAddInput(input), self.session.canAddOutput(self.photoOutput) else { return }
            self.session.sessionPreset = .photo
            self.session.addInput(input)
            self.session.addOutput(self.photoOutput)
            self.currentDevice = camera
            self.start()
        }
    }

    private func start() {
        guard !session.isRunning else { return }
        session.startRunning()
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capturePhoto(completion: @escaping (UIImage) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            settings.flashMode = self.flashEnabled && self.photoOutput.supportedFlashModes.contains(.on) ? .on : .off
            self.captureCompletion = completion
            self.isCapturing = true
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self, let current = self.currentDevice else { return }
            let position: AVCaptureDevice.Position = current.position == .back ? .front : .back
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let input = try? AVCaptureDeviceInput(device: camera) else { return }
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            if self.session.canAddInput(input) { self.session.addInput(input); self.currentDevice = camera }
            self.session.commitConfiguration()
        }
    }

    func toggleFlash() { flashEnabled.toggle() }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let completion = captureCompletion
        isCapturing = false
        captureCompletion = nil
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { completion?(image) }
    }
}

struct SWCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

enum SystemSettings {
    @MainActor static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
