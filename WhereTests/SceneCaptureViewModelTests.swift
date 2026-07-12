import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Where

@Test func captureCanvasUsesWhereSemanticBackground() {
    #expect(CaptureCanvasPolicy.backgroundAssetName == "WhereCanvas")
    #expect(CaptureCanvasPolicy.fieldSurfaceAssetName == "WhereSurface")
}

@Test func captureInitialSourceUsesCameraWhenAvailableAndPhotosOtherwise() {
    #expect(CaptureInitialSource.destination(for: .available) == .camera)
    #expect(CaptureInitialSource.destination(for: .unavailable) == .photos)
    #expect(CaptureInitialSource.destination(for: .denied) == .permissionRecovery)
}

@Test func systemCameraExposesLibraryAction() {
    #expect(CameraPickerAction.library.accessibilityLabel == "从相册选择")
}

@Test func captureFormOnlyAppearsAfterPhotoIsReady() {
    #expect(!CapturePresentationPolicy.showsForm(hasSceneImage: false))
    #expect(CapturePresentationPolicy.showsForm(hasSceneImage: true))
}

@MainActor
struct SceneCaptureViewModelTests {
    @Test func sceneNameIsRequiredBeforeEditingMarkers() throws {
        let harness = try CaptureHarness()
        harness.model.sceneImageSize = CGSize(width: 400, height: 300)

        #expect(harness.model.beginMarking() == false)
        #expect(harness.model.validationMessage == "请输入场景名称。")

        harness.model.sceneName = "  书房  "
        #expect(harness.model.beginMarking())
        #expect(harness.model.sceneName == "书房")
    }

	@Test func scenePreviewIsDownsampledForDisplay() async throws {
		let harness = try CaptureHarness()
		let image = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1200)).image { context in
			UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200))
		}
		let data = try #require(image.jpegData(compressionQuality: 0.8))
		try await harness.model.setSceneImage(data: data, pixelSize: image.size)
		let preview = try #require(harness.model.sceneImage)
		#expect(max(preview.size.width, preview.size.height) <= 1600)
		#expect(harness.model.sceneImageSize == image.size)
	}

	@Test func lateSceneStageCannotResurrectCancelledCapture() async throws {
		let harness = try CaptureHarness()
		let image = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000)).image { context in
			UIColor.purple.setFill(); context.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000))
		}
		let data = try #require(image.jpegData(compressionQuality: 0.9))
		let staging = Task { try await harness.model.setSceneImage(data: data, pixelSize: image.size) }
		await Task.yield()
		#expect(await harness.model.cancel())
		try await staging.value
		#expect(harness.model.sceneImageDraft == nil)
		#expect(harness.model.sceneImage == nil)
		#expect(harness.draftFilenames().isEmpty)
	}

	@Test func lateAppearanceStageCannotResurrectDismissedItem() async throws {
		let harness = try CaptureHarness()
		harness.model.beginItem(atNormalizedPoint: CGPoint(x: 0.4, y: 0.4))
		harness.model.pendingItem?.name = "Late"
		let image = UIGraphicsImageRenderer(size: CGSize(width: 2600, height: 1800)).image { context in
			UIColor.cyan.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2600, height: 1800))
		}
		let data = try #require(image.jpegData(compressionQuality: 0.9))
		let staging = Task { try await harness.model.setPendingAppearance(originalData: data, cutout: nil, preview: image) }
		await Task.yield()
		harness.model.dismissPendingItem()
		try await staging.value
		#expect(harness.model.pendingItem == nil)
		#expect(harness.draftFilenames().isEmpty)
	}

    @Test func letterboxTapIsIgnoredAndValidTapCreatesPendingItem() throws {
        let harness = try CaptureHarness()
        harness.model.sceneImageSize = CGSize(width: 200, height: 100)

        #expect(harness.model.beginItem(at: CGPoint(x: 100, y: 20), in: CGSize(width: 200, height: 200)) == false)
        #expect(harness.model.pendingItem == nil)
        #expect(harness.model.beginItem(at: CGPoint(x: 50, y: 75), in: CGSize(width: 200, height: 200)))
        #expect(harness.model.pendingItem?.normalizedPoint == CGPoint(x: 0.25, y: 0.25))
    }

	@Test func markerDragUsesCanvasCoordinatesRatherThanMarkerLocalCoordinates() {
		let point = MarkerDragMapper.normalizedLocation(
			CGPoint(x: 300, y: 200),
			imageSize: CGSize(width: 400, height: 200),
			containerSize: CGSize(width: 400, height: 400)
		)
		#expect(point == CGPoint(x: 0.75, y: 0.5))
		#expect(MarkerDragMapper.normalizedLocation(
			CGPoint(x: 22, y: 22),
			imageSize: CGSize(width: 400, height: 200),
			containerSize: CGSize(width: 400, height: 400)
		) == nil)
	}

    @Test func itemNameIsRequiredAndTokensAreTrimmedAndDeduplicated() throws {
        let harness = try CaptureHarness()
        harness.model.beginItem(atNormalizedPoint: CGPoint(x: 0.2, y: 0.3))
        harness.model.pendingItem?.aliasesText = " 充电线, Cable，Ｃａｂｌｅ\n备用 "
        harness.model.pendingItem?.tagsText = "电子, 电子，旅行"

        #expect(harness.model.commitPendingItem() == false)
        harness.model.pendingItem?.name = "  数据线 "
        #expect(harness.model.commitPendingItem())
        #expect(harness.model.items.count == 1)
        #expect(harness.model.items[0].name == "数据线")
        #expect(harness.model.items[0].aliases == ["充电线", "Cable", "备用"])
        #expect(harness.model.items[0].tags == ["电子", "旅行"])
    }

    @Test func multiplePinsCanMoveEditAndRemove() throws {
        let harness = try CaptureHarness()
        harness.addItem(name: "钥匙", point: CGPoint(x: 0.1, y: 0.2))
        harness.addItem(name: "耳机", point: CGPoint(x: 0.7, y: 0.8))
        let firstID = harness.model.items[0].id

        harness.model.moveItem(id: firstID, to: CGPoint(x: 1.2, y: -0.2))
        #expect(harness.model.items[0].normalizedPoint == CGPoint(x: 1, y: 0))
        harness.model.editItem(id: firstID)
        harness.model.pendingItem?.name = "车钥匙"
        #expect(harness.model.commitPendingItem())
        #expect(harness.model.items.map(\.name) == ["车钥匙", "耳机"])
        harness.model.removeItem(id: firstID)
        #expect(harness.model.items.map(\.name) == ["耳机"])
    }

    @Test func finishSavesDatabaseBeforePromotionAndPreventsDuplicateSubmission() async throws {
        let harness = try CaptureHarness(saveBehavior: .suspend)
        try await harness.stageScene()
        harness.model.sceneName = "玄关"
        harness.addItem(name: "钥匙", point: CGPoint(x: 0.4, y: 0.5))

        let first = Task { await harness.model.finish() }
        await harness.repository.waitUntilSaving()
        #expect(harness.model.isSaving)
        await harness.model.finish()
        #expect(await harness.repository.saveCount == 1)
        await harness.repository.resume()
        await first.value

        #expect(harness.model.didFinish)
        let saved = try #require(await harness.repository.lastDraft)
        #expect(saved.name == "玄关")
        #expect(saved.imagePath.hasPrefix("Images/"))
        #expect(saved.items.count == 1)
		#expect(await harness.repository.saveObservedDraftFilesOnly)
    }

    @Test func failedSaveRestoresStagingAndRetrySucceeds() async throws {
        let harness = try CaptureHarness(saveBehavior: .failOnce)
        try await harness.stageScene()
        harness.model.sceneName = "客厅"
        harness.addItem(name: "遥控器", point: CGPoint(x: 0.5, y: 0.5))

        await harness.model.finish()
        #expect(harness.model.didFinish == false)
        #expect(harness.model.saveErrorMessage != nil)
        #expect(harness.model.hasStagedImages)
        await harness.model.finish()
        #expect(harness.model.didFinish)
        #expect(await harness.repository.saveCount == 2)
    }

    @Test func cancelDiscardsAllStagedImages() async throws {
        let harness = try CaptureHarness()
        try await harness.stageScene()
        #expect(harness.model.hasStagedImages)
        await harness.model.cancel()
        #expect(harness.model.hasStagedImages == false)
		#expect(harness.draftFilenames().isEmpty)
    }

	@Test func savedDraftIncludesNotesAndBothAppearancePaths() async throws {
		let harness = try CaptureHarness()
		try await harness.stageScene()
		harness.model.sceneName = "储物间"
		harness.model.beginItem(atNormalizedPoint: CGPoint(x: 0.3, y: 0.6))
		harness.model.pendingItem?.name = "工具箱"
		harness.model.pendingItem?.locationNote = "上层右侧"
		harness.model.pendingItem?.note = "内有螺丝刀"
		let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { context in
			UIColor.red.setFill(); context.fill(CGRect(x: 2, y: 2, width: 8, height: 8))
		}
		let data = try #require(image.pngData())
		try await harness.model.setPendingAppearance(originalData: data, cutout: try #require(image.cgImage), preview: image)
		#expect(harness.model.commitPendingItem())

		await harness.model.finish()
		let item = try #require(await harness.repository.lastDraft?.items.first)
		#expect(item.locationNote == "上层右侧")
		#expect(item.note == "内有螺丝刀")
		#expect(item.appearanceOriginalImagePath?.hasPrefix("Images/") == true)
		#expect(item.appearanceCutoutImagePath?.hasPrefix("Images/") == true)
	}

	@Test func promotionFailureCompensatesDatabaseAndRemainsRetryable() async throws {
		let harness = try CaptureHarness()
		try await harness.stageScene()
		harness.model.sceneName = "卧室"
		let name = try #require(harness.model.sceneImageDraft?.relativeName)
		let collision = harness.root.appending(path: "Images/\(name)")
		try Data([1]).write(to: collision)

		await harness.model.finish()
		#expect(harness.model.didFinish == false)
		#expect(await harness.repository.rollbackCount == 1)
		#expect(FileManager.default.fileExists(atPath: harness.root.appending(path: "Drafts/\(name)").path))
		if FileManager.default.fileExists(atPath: collision.path) { try FileManager.default.removeItem(at: collision) }
		await harness.model.finish()
		#expect(harness.model.didFinish)
	}

	@Test func cancelBlocksCleanupUntilPendingDatabaseCompensationSucceeds() async throws {
		let harness = try CaptureHarness(rollbackFailures: 2)
		try await harness.stageScene()
		harness.model.sceneName = "厨房"
		let name = try #require(harness.model.sceneImageDraft?.relativeName)
		let draftURL = harness.root.appending(path: "Drafts/\(name)")
		try Data([1]).write(to: harness.root.appending(path: "Images/\(name)"))

		await harness.model.finish()
		#expect(harness.model.hasCommittedGraphPendingCompensation)
		#expect(FileManager.default.fileExists(atPath: draftURL.path))
		#expect(await harness.model.cancel() == false)
		#expect(harness.model.hasCommittedGraphPendingCompensation)
		#expect(harness.model.saveErrorMessage?.contains("无法取消") == true)
		#expect(FileManager.default.fileExists(atPath: draftURL.path))

		#expect(await harness.model.cancel())
		#expect(harness.model.hasCommittedGraphPendingCompensation == false)
		#expect(FileManager.default.fileExists(atPath: draftURL.path) == false)
		#expect(await harness.repository.rollbackCount == 3)
	}

	@Test func appearanceFailureIsActionableAndDoesNotLosePendingItem() throws {
		let harness = try CaptureHarness()
		harness.model.beginItem(atNormalizedPoint: CGPoint(x: 0.5, y: 0.5))
		harness.model.pendingItem?.name = "护照"
		harness.model.reportAppearanceError(ImageStoreError.invalidImage, step: "读取")
		#expect(harness.model.appearanceErrorMessage?.contains("读取") == true)
		#expect(harness.model.pendingItem?.name == "护照")
	}

	@Test func appStartupRecoversCrashAfterDatabaseCommitAndPromotion() async throws {
		let dependencies = try AppDependencies.testing()
		let sceneID = UUID()
		let draft = try await dependencies.imageStore.stageSceneImage(CaptureHarness.testJPEG())
		try await dependencies.imageStore.prepareCaptureCommit(sceneID: sceneID, drafts: [draft])
		let finalPath = "Images/\(draft.relativeName)"
		try await dependencies.itemRepository.saveSceneDraft(SceneDraft(id: sceneID, name: "Crash", imagePath: finalPath, items: []))
		_ = try await dependencies.imageStore.promote([draft])

		try await dependencies.recoverInterruptedCaptureIfNeeded()

		await #expect(throws: RepositoryError.self) { try await dependencies.sceneRepository.fetchScene(id: sceneID) }
		#expect(try await dependencies.imageStore.pendingCaptureCommit() == nil)
		#expect(await dependencies.imageStore.loadImage(relativePath: finalPath) == nil)
	}

	@Test func cancelingAnAppearanceReplacementKeepsStoredDraftAndDiscardsReplacement() async throws {
		let harness = try CaptureHarness()
		try await harness.stageScene()
		harness.model.beginItem(atNormalizedPoint: CGPoint(x: 0.5, y: 0.5))
		harness.model.pendingItem?.name = "相机"
		let firstImage = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { context in
			UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
		}
		let firstData = try #require(firstImage.jpegData(compressionQuality: 0.9))
		try await harness.model.setPendingAppearance(originalData: firstData, cutout: nil, preview: firstImage)
		#expect(harness.model.commitPendingItem())
		let id = harness.model.items[0].id
		let originalName = try #require(harness.model.items[0].appearanceOriginal?.relativeName)
		harness.model.editItem(id: id)
		let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { context in
			UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
		}
		let data = try #require(image.jpegData(compressionQuality: 0.9))
		try await harness.model.setPendingAppearance(originalData: data, cutout: nil, preview: image)
		#expect(harness.model.stagedImageCount == 2)
		harness.model.dismissPendingItem()
		await Task.yield()
		#expect(harness.model.stagedImageCount == 2)
		#expect(harness.model.items[0].appearanceOriginal?.relativeName == originalName)
	}
}

private actor CaptureRepositorySpy: @preconcurrency ItemRepositoryProtocol {
    enum Behavior { case succeed, failOnce, suspend }
    enum Failure: Error { case forced }
    private var behavior: Behavior
    private(set) var saveCount = 0
    private(set) var lastDraft: SceneDraft?
	private(set) var rollbackCount = 0
	private(set) var saveObservedDraftFilesOnly = false
	private let root: URL
	private var rollbackFailuresRemaining: Int
    private var savingContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

	init(behavior: Behavior, root: URL, rollbackFailures: Int) {
		self.behavior = behavior
		self.root = root
		rollbackFailuresRemaining = rollbackFailures
	}

    func saveSceneDraft(_ draft: SceneDraft) async throws {
        saveCount += 1
        lastDraft = draft
		let relativePaths = [draft.imagePath] + draft.items.flatMap { [$0.appearanceOriginalImagePath, $0.appearanceCutoutImagePath].compactMap { $0 } }
		saveObservedDraftFilesOnly = relativePaths.allSatisfy { path in
			let name = URL(fileURLWithPath: path).lastPathComponent
			return FileManager.default.fileExists(atPath: root.appending(path: "Drafts/\(name)").path)
				&& !FileManager.default.fileExists(atPath: root.appending(path: path).path)
		}
        if behavior == .failOnce {
            behavior = .succeed
            throw Failure.forced
        }
        if behavior == .suspend {
            savingContinuation?.resume()
            savingContinuation = nil
            await withCheckedContinuation { resumeContinuation = $0 }
            behavior = .succeed
        }
    }
	func rollbackSceneDraft(id: UUID) async throws {
		rollbackCount += 1
		if rollbackFailuresRemaining > 0 {
			rollbackFailuresRemaining -= 1
			throw Failure.forced
		}
	}

    func waitUntilSaving() async {
        if saveCount > 0 { return }
        await withCheckedContinuation { savingContinuation = $0 }
    }
    func resume() { resumeContinuation?.resume(); resumeContinuation = nil }
    func searchItems(query: String) async throws -> [ItemSummary] { [] }
    func observeItems(query: String) -> AsyncThrowingStream<[ItemSummary], Error> { .init { $0.finish() } }
    func deleteItem(id: UUID) async throws -> DeletedImagePaths { .init(original: nil, cutout: nil) }
}

@MainActor
private final class CaptureHarness {
    let model: SceneCaptureViewModel
    let repository: CaptureRepositorySpy
	let root: URL
	private let imageStore: ImageStore

	init(saveBehavior: CaptureRepositorySpy.Behavior = .succeed, rollbackFailures: Int = 0) throws {
		root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        imageStore = try ImageStore(rootDirectory: root)
		repository = CaptureRepositorySpy(behavior: saveBehavior, root: root, rollbackFailures: rollbackFailures)
        model = SceneCaptureViewModel(repository: repository, imageStore: imageStore)
    }

	func draftFilenames() -> [String] {
		(try? FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Drafts").path)) ?? []
	}

    func stageScene() async throws {
		try await model.setSceneImage(data: Self.testJPEG(), pixelSize: CGSize(width: 16, height: 12))
	}

	static func testJPEG() throws -> Data {
		let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 12)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 12))
        }
		return try #require(image.jpegData(compressionQuality: 0.9))
    }

    func addItem(name: String, point: CGPoint) {
        model.beginItem(atNormalizedPoint: point)
        model.pendingItem?.name = name
        _ = model.commitPendingItem()
    }
}
