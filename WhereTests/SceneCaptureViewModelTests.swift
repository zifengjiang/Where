import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Where

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

    @Test func letterboxTapIsIgnoredAndValidTapCreatesPendingItem() throws {
        let harness = try CaptureHarness()
        harness.model.sceneImageSize = CGSize(width: 200, height: 100)

        #expect(harness.model.beginItem(at: CGPoint(x: 100, y: 20), in: CGSize(width: 200, height: 200)) == false)
        #expect(harness.model.pendingItem == nil)
        #expect(harness.model.beginItem(at: CGPoint(x: 50, y: 75), in: CGSize(width: 200, height: 200)))
        #expect(harness.model.pendingItem?.normalizedPoint == CGPoint(x: 0.25, y: 0.25))
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

    @Test func finishPromotesThenSavesAndPreventsDuplicateSubmission() async throws {
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
    private var savingContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    init(behavior: Behavior) { self.behavior = behavior }

    func saveSceneDraft(_ draft: SceneDraft) async throws {
        saveCount += 1
        lastDraft = draft
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
    private let imageStore: ImageStore

    init(saveBehavior: CaptureRepositorySpy.Behavior = .succeed) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        imageStore = try ImageStore(rootDirectory: root)
        repository = CaptureRepositorySpy(behavior: saveBehavior)
        model = SceneCaptureViewModel(repository: repository, imageStore: imageStore)
    }

    func stageScene() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 12)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 12))
        }
        let data = try #require(image.jpegData(compressionQuality: 0.9))
        try await model.setSceneImage(data: data, pixelSize: CGSize(width: 16, height: 12))
    }

    func addItem(name: String, point: CGPoint) {
        model.beginItem(atNormalizedPoint: point)
        model.pendingItem?.name = name
        _ = model.commitPendingItem()
    }
}
