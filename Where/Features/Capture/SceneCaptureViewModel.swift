import CoreGraphics
import Foundation
import Observation
import UIKit
import ImageIO

enum SceneCaptureStep: Equatable {
    case source
    case details
    case markers
}

struct CaptureItemDraft: Identifiable, Equatable {
    let id: UUID
    var name: String
    var aliasesText: String
    var tagsText: String
    var locationNote: String
    var note: String
    var normalizedPoint: CGPoint
    var aliases: [String]
    var tags: [String]
    var appearanceOriginal: ImageStore.DraftImage?
    var appearanceCutout: ImageStore.DraftImage?
    var appearancePreview: UIImage?

    static func new(at point: CGPoint) -> Self {
        Self(
            id: UUID(), name: "", aliasesText: "", tagsText: "", locationNote: "", note: "",
            normalizedPoint: point, aliases: [], tags: [], appearanceOriginal: nil,
            appearanceCutout: nil, appearancePreview: nil
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.aliasesText == rhs.aliasesText
            && lhs.tagsText == rhs.tagsText && lhs.locationNote == rhs.locationNote
            && lhs.note == rhs.note && lhs.normalizedPoint == rhs.normalizedPoint
            && lhs.aliases == rhs.aliases && lhs.tags == rhs.tags
            && lhs.appearanceOriginal?.relativeName == rhs.appearanceOriginal?.relativeName
            && lhs.appearanceCutout?.relativeName == rhs.appearanceCutout?.relativeName
    }
}

@MainActor
@Observable
final class SceneCaptureViewModel {
    private let repository: any ItemRepositoryProtocol
    private let imageStore: ImageStore

    let sceneID: UUID
    private(set) var step: SceneCaptureStep = .source
    var sceneName = ""
    var sceneImage: UIImage?
    var sceneImageSize: CGSize = .zero
    private(set) var sceneImageDraft: ImageStore.DraftImage?
    private(set) var items: [CaptureItemDraft] = []
    var pendingItem: CaptureItemDraft?
    private var editingItemID: UUID?
    private(set) var validationMessage: String?
    private(set) var imageErrorMessage: String?
	private(set) var appearanceErrorMessage: String?
    private(set) var saveErrorMessage: String?
    private(set) var isSaving = false
    private(set) var isProcessingImage = false
    private(set) var didFinish = false
	private(set) var hasCommittedGraphPendingCompensation = false
	private var sceneImageGeneration = UUID()
	private var appearanceGeneration = UUID()
	private var isCancelled = false

    var hasStagedImages: Bool { !allDraftImages.isEmpty }
	var stagedImageCount: Int { allDraftImages.count }
    var canFinish: Bool { sceneImageDraft != nil && !trim(sceneName).isEmpty && !isSaving }

    init(
        sceneID: UUID = UUID(),
        repository: any ItemRepositoryProtocol,
        imageStore: ImageStore
    ) {
        self.sceneID = sceneID
        self.repository = repository
        self.imageStore = imageStore
    }

    func setSceneImage(data: Data, pixelSize: CGSize? = nil) async throws {
		guard !isCancelled, !isProcessingImage else { return }
		let generation = UUID()
		sceneImageGeneration = generation
        isProcessingImage = true
		defer { isProcessingImage = false }
        let staged = try await imageStore.stageSceneImage(data)
		guard sceneImageGeneration == generation else {
			await imageStore.discard([staged])
			return
		}
		let image = await Task.detached(priority: .userInitiated) {
			guard let source = CGImageSourceCreateWithURL(staged.url as CFURL, nil),
				  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
					kCGImageSourceCreateThumbnailFromImageAlways: true,
					kCGImageSourceCreateThumbnailWithTransform: true,
					kCGImageSourceThumbnailMaxPixelSize: 1600,
				  ] as CFDictionary) else { return nil as UIImage? }
			return UIImage(cgImage: cgImage)
		}.value
		guard sceneImageGeneration == generation else {
			await imageStore.discard([staged])
			return
		}
        guard let image else {
            await imageStore.discard([staged])
            throw ImageStoreError.invalidImage
        }
        if let old = sceneImageDraft { await imageStore.discard([old]) }
        sceneImageDraft = staged
        sceneImage = image
        sceneImageSize = pixelSize ?? image.size
        imageErrorMessage = nil
        step = .details
    }

    func reportImageError(_ error: Error) {
        imageErrorMessage = "无法读取照片，请重新选择。\n\(error.localizedDescription)"
    }

	func reportAppearanceError(_ error: Error, step: String) {
		appearanceErrorMessage = "物品照片\(step)失败，当前资料已保留，请重新选择。\n\(error.localizedDescription)"
	}

    @discardableResult
    func beginMarking() -> Bool {
        let name = trim(sceneName)
        guard !name.isEmpty else {
            validationMessage = "请输入场景名称。"
            return false
        }
        guard sceneImageDraft != nil || sceneImageSize.width > 0 else {
            validationMessage = "请先选择场景照片。"
            return false
        }
        sceneName = name
        validationMessage = nil
        step = .markers
        return true
    }

    @discardableResult
    func beginItem(at viewPoint: CGPoint, in containerSize: CGSize) -> Bool {
        let geometry = AspectFitGeometry(imageSize: sceneImageSize, containerSize: containerSize)
        guard let point = geometry.normalizedPoint(for: viewPoint) else { return false }
        beginItem(atNormalizedPoint: point)
        return true
    }

    func beginItem(atNormalizedPoint point: CGPoint) {
        guard point.x.isFinite, point.y.isFinite else { return }
        editingItemID = nil
        pendingItem = .new(at: clamped(point))
        validationMessage = nil
    }

    func editItem(id: UUID) {
        guard var item = items.first(where: { $0.id == id }) else { return }
        item.aliasesText = item.aliases.joined(separator: ", ")
        item.tagsText = item.tags.joined(separator: ", ")
        editingItemID = id
        pendingItem = item
    }

    @discardableResult
    func commitPendingItem() -> Bool {
        guard var item = pendingItem else { return false }
        item.name = trim(item.name)
        guard !item.name.isEmpty else {
            validationMessage = "请输入物品名称。"
            return false
        }
        item.locationNote = trim(item.locationNote)
        item.note = trim(item.note)
        item.aliases = tokens(from: item.aliasesText)
        item.tags = tokens(from: item.tagsText)
        if let editingItemID, let index = items.firstIndex(where: { $0.id == editingItemID }) {
			let previous = items[index]
            items[index] = item
			let discarded = replacedAppearanceDrafts(old: previous, new: item)
			if !discarded.isEmpty { Task { await imageStore.discard(discarded) } }
        } else {
            items.append(item)
        }
        self.editingItemID = nil
        pendingItem = nil
        validationMessage = nil
        return true
    }

    func dismissPendingItem() {
		appearanceGeneration = UUID()
        let pending = pendingItem
        pendingItem = nil
        editingItemID = nil
		guard let pending else { return }
		let drafts: [ImageStore.DraftImage]
		if let stored = items.first(where: { $0.id == pending.id }) {
			drafts = replacedAppearanceDrafts(old: pending, new: stored)
		} else {
			drafts = [pending.appearanceOriginal, pending.appearanceCutout].compactMap { $0 }
		}
        Task { await imageStore.discard(drafts) }
    }

    func moveItem(id: UUID, to point: CGPoint) {
        guard point.x.isFinite, point.y.isFinite,
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].normalizedPoint = clamped(point)
    }

    func removeItem(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: index)
        let drafts = [removed.appearanceOriginal, removed.appearanceCutout].compactMap { $0 }
        Task { await imageStore.discard(drafts) }
    }

    func setPendingAppearance(originalData: Data, cutout: CGImage?, preview: UIImage) async throws {
        guard var pending = pendingItem else { return }
		let generation = UUID()
		appearanceGeneration = generation
		let pendingID = pending.id
		isProcessingImage = true
		defer { isProcessingImage = false }
        let original = try await imageStore.stageAppearanceOriginal(originalData)
        var cutoutDraft: ImageStore.DraftImage?
        do {
            if let cutout { cutoutDraft = try await imageStore.stageCutout(cutout) }
        } catch {
            await imageStore.discard([original])
            throw error
        }
		guard appearanceGeneration == generation, pendingItem?.id == pendingID else {
			var lateDrafts = [original]
			if let cutoutDraft { lateDrafts.append(cutoutDraft) }
			await imageStore.discard(lateDrafts)
			return
		}
		let stored = items.first(where: { $0.id == pending.id })
		let old: [ImageStore.DraftImage] = [pending.appearanceOriginal, pending.appearanceCutout].compactMap { draft -> ImageStore.DraftImage? in
			guard let draft else { return nil }
			guard draft.relativeName != stored?.appearanceOriginal?.relativeName,
				  draft.relativeName != stored?.appearanceCutout?.relativeName else { return nil }
			return draft
		}
        pending.appearanceOriginal = original
        pending.appearanceCutout = cutoutDraft
        pending.appearancePreview = preview
        pendingItem = pending
		appearanceErrorMessage = nil
        await imageStore.discard(old)
    }

    func finish() async {
        guard !isSaving, !didFinish else { return }
        guard beginMarking(), let sceneImageDraft else { return }
        isSaving = true
        saveErrorMessage = nil
        let staged = allDraftImages
		let pathByName = Dictionary(uniqueKeysWithValues: staged.map { ($0.relativeName, "Images/\($0.relativeName)") })
		let databaseDraft = makeSceneDraft(
			scenePath: pathByName[sceneImageDraft.relativeName]!,
			paths: pathByName
		)
        do {
			try await imageStore.prepareCaptureCommit(sceneID: sceneID, drafts: staged)
			try await repository.saveSceneDraft(databaseDraft)
			hasCommittedGraphPendingCompensation = true
            do {
				_ = try await imageStore.promote(staged)
				try await imageStore.clearPendingCaptureCommit()
				hasCommittedGraphPendingCompensation = false
                didFinish = true
                self.sceneImageDraft = nil
                for index in items.indices {
                    items[index].appearanceOriginal = nil
                    items[index].appearanceCutout = nil
                }
            } catch {
				let promotionError = error
				do {
					try await imageStore.reconcileToDrafts(staged)
				} catch {
					saveErrorMessage = "图片整理中断，恢复草稿尚未完成。所有路径已记录，请重试保存或取消以安全清理。"
					isSaving = false
					return
				}
				do {
					try await repository.rollbackSceneDraft(id: sceneID)
					hasCommittedGraphPendingCompensation = false
					try await imageStore.clearPendingCaptureCommit()
				} catch {
					saveErrorMessage = "图片整理失败，数据库补偿也未完成。草稿和已提交记录均已保留；请重试保存，或取消以再次尝试安全清理。"
                    isSaving = false
                    return
                }
				throw promotionError
            }
        } catch {
			if !hasCommittedGraphPendingCompensation { try? await imageStore.clearPendingCaptureCommit() }
            saveErrorMessage = "保存失败，草稿已保留，可以重试。\n\(error.localizedDescription)"
        }
        isSaving = false
    }

	@discardableResult
    func cancel() async -> Bool {
		guard !isSaving else { return false }
		isCancelled = true
		sceneImageGeneration = UUID()
		appearanceGeneration = UUID()
		if hasCommittedGraphPendingCompensation {
			do {
				try await repository.rollbackSceneDraft(id: sceneID)
				if let record = try await imageStore.pendingCaptureCommit() {
					try await imageStore.discardFiles(for: record)
				}
				try await imageStore.clearPendingCaptureCommit()
				hasCommittedGraphPendingCompensation = false
			} catch {
				saveErrorMessage = "暂时无法取消：已提交记录尚未安全清理。草稿仍完整保留，请稍后重试取消或重新保存。\n\(error.localizedDescription)"
				return false
			}
		}
		await imageStore.discard(allDraftImages)
        sceneImageDraft = nil
		sceneImage = nil
		sceneImageSize = .zero
        items.removeAll()
        pendingItem = nil
		return true
    }

    private var allDraftImages: [ImageStore.DraftImage] {
        var values: [ImageStore.DraftImage] = []
        if let sceneImageDraft { values.append(sceneImageDraft) }
        for item in items {
            if let value = item.appearanceOriginal { values.append(value) }
            if let value = item.appearanceCutout { values.append(value) }
        }
        if let pendingItem, !items.contains(where: { $0.id == pendingItem.id }) {
            if let value = pendingItem.appearanceOriginal { values.append(value) }
            if let value = pendingItem.appearanceCutout { values.append(value) }
        }
        return values
    }

    private func makeSceneDraft(scenePath: String, paths: [String: String]) -> SceneDraft {
        SceneDraft(
            id: sceneID, name: trim(sceneName), imagePath: scenePath,
            items: items.map { item in
                ItemDraft(
                    id: item.id, name: item.name, locationNote: optional(item.locationNote),
                    note: optional(item.note), normalizedX: item.normalizedPoint.x,
                    normalizedY: item.normalizedPoint.y, aliases: item.aliases, tags: item.tags,
                    appearanceOriginalImagePath: item.appearanceOriginal.flatMap { paths[$0.relativeName] },
                    appearanceCutoutImagePath: item.appearanceCutout.flatMap { paths[$0.relativeName] }
                )
            }
        )
    }

    private func tokens(from text: String) -> [String] {
        var seen: Set<String> = []
        return text.components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map(trim)
            .filter { value in
                let key = SearchNormalizer.normalize(value)
                return !key.isEmpty && seen.insert(key).inserted
            }
    }

    private func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func optional(_ value: String) -> String? { value.isEmpty ? nil : value }
	private func replacedAppearanceDrafts(old: CaptureItemDraft, new: CaptureItemDraft) -> [ImageStore.DraftImage] {
		let retained = Set([new.appearanceOriginal?.relativeName, new.appearanceCutout?.relativeName].compactMap { $0 })
		return [old.appearanceOriginal, old.appearanceCutout].compactMap { draft in
			guard let draft, !retained.contains(draft.relativeName) else { return nil }
			return draft
		}
	}
    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
    }
}
