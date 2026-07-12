import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Where

struct ImageStoreTests {
    @Test func initRejectsSymlinkedOwnedDirectories() throws {
        for component in ["Drafts", "Images"] {
            let root = temporaryRoot()
            let external = temporaryRoot()
            defer { remove(root); remove(external) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: root.appending(path: component), withDestinationURL: external)
            #expect(throws: ImageStoreError.self) { try ImageStore(rootDirectory: root) }
        }
    }

    @Test func replacingDraftsWithSymlinkRejectsStageAndDiscardWithoutTouchingVictim() async throws {
        let (store, root) = try makeStore(); defer { remove(root) }
        let draft = try await store.stageSceneImage(jpeg(width: 10, height: 10))
        let external = temporaryRoot(); defer { remove(external) }
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let victim = external.appending(path: draft.relativeName); try Data([42]).write(to: victim)
        try FileManager.default.removeItem(at: root.appending(path: "Drafts"))
        try FileManager.default.createSymbolicLink(at: root.appending(path: "Drafts"), withDestinationURL: external)
        await #expect(throws: ImageStoreError.self) { try await store.stageSceneImage(jpeg(width: 11, height: 11)) }
        await store.discard([draft])
        #expect((try Data(contentsOf: victim)) == Data([42]))
    }

    @Test func replacingImagesWithSymlinkRejectsPromoteDeleteAndCleanupWithoutTouchingVictim() async throws {
        let (store, root) = try makeStore(); defer { remove(root) }
        let draft = try await store.stageSceneImage(jpeg(width: 10, height: 10))
        let external = temporaryRoot(); defer { remove(external) }
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let victim = external.appending(path: draft.relativeName); try Data([42]).write(to: victim)
        try FileManager.default.removeItem(at: root.appending(path: "Images"))
        try FileManager.default.createSymbolicLink(at: root.appending(path: "Images"), withDestinationURL: external)
        await #expect(throws: ImageStoreError.self) { try await store.promote([draft]) }
        await #expect(throws: ImageStoreError.self) { try await store.delete(relativePaths: ["Images/\(draft.relativeName)"]) }
        await #expect(throws: ImageStoreError.self) { try await store.cleanOrphans(referencedPaths: [], olderThan: .now) }
        #expect((try Data(contentsOf: victim)) == Data([42]))
    }

    @Test func createsDraftDirectoriesAndUniqueDrafts() async throws {
        let (store, root) = try makeStore(); defer { remove(root) }
        let data = try jpeg(width: 20, height: 10)
        let first = try await store.stageSceneImage(data)
        let second = try await store.stageSceneImage(data)
        #expect(first.url.deletingLastPathComponent().standardizedFileURL.path == root.appending(path: "Drafts").standardizedFileURL.path)
        #expect(first.relativeName != second.relativeName)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Images").path))
    }

    @Test func sceneJPEGNormalizesOrientationAndCapsLongestEdge() async throws {
        let (store, root) = try makeStore(); defer { remove(root) }
        let draft = try await store.stageSceneImage(jpeg(width: 4000, height: 2000, orientation: 6))
        let properties = try imageProperties(draft.url)
        #expect(draft.url.pathExtension == "jpg")
        #expect(properties.width == 1536)
        #expect(properties.height == 3072)
        #expect(properties.orientation == 1)
    }

    @Test func appearanceOriginalIsCompressedAndCapped() async throws {
        let (store, root) = try makeStore(); defer { remove(root) }
        let input = try jpeg(width: 2400, height: 1200, noisy: true)
        let draft = try await store.stageAppearanceOriginal(input)
        let properties = try imageProperties(draft.url)
        #expect(properties.width == 1600)
        #expect(properties.height == 800)
        #expect((try Data(contentsOf: draft.url)).count < input.count)
    }

    @Test func cutoutPersistsPNGWithAlpha() async throws {
        let (store, root) = try makeStore(); defer { remove(root) }
        let draft = try await store.stageCutout(alphaImage(width: 32, height: 24))
        let source = CGImageSourceCreateWithURL(draft.url as CFURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        #expect(draft.url.pathExtension == "png")
        #expect(image.width == 32 && image.height == 24)
        #expect(image.alphaInfo != .none && image.alphaInfo != .noneSkipFirst && image.alphaInfo != .noneSkipLast)
        let alphas = [alphaValue(image, x: 4, y: 12), alphaValue(image, x: 28, y: 12)]
        #expect(alphas.contains(0))
        #expect(alphas.contains { (110...145).contains($0) })
    }

    @Test func promoteMovesDraftsInInputOrderAndNeverOverwrites() async throws {
        let (store, root) = try makeStore(); defer { remove(root) }
        let a = try await store.stageSceneImage(jpeg(width: 11, height: 9))
        let b = try await store.stageSceneImage(jpeg(width: 12, height: 8))
        let paths = try await store.promote([b, a])
        #expect(paths == ["Images/\(b.relativeName)", "Images/\(a.relativeName)"])
        #expect(!FileManager.default.fileExists(atPath: a.url.path))
        #expect(paths.allSatisfy { FileManager.default.fileExists(atPath: root.appending(path: $0).path) })
        let forged = ImageStore.DraftImage(url: root.appending(path: "Drafts").appending(path: b.relativeName), relativeName: b.relativeName)
        try Data([1]).write(to: forged.url)
        await #expect(throws: ImageStoreError.self) { try await store.promote([forged]) }
        #expect((try Data(contentsOf: root.appending(path: paths[0]))) != Data([1]))

        let rollback = try await store.stageSceneImage(jpeg(width: 13, height: 7))
        await #expect(throws: ImageStoreError.self) { try await store.promote([rollback, forged]) }
        #expect(FileManager.default.fileExists(atPath: rollback.url.path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Images/\(rollback.relativeName)").path))
    }

    @Test func discardIsIdempotentAndDeleteIgnoresMissing() async throws {
        let (store, root) = try makeStore(); defer { remove(root) }
        let draft = try await store.stageSceneImage(jpeg(width: 10, height: 10))
        await store.discard([draft]); await store.discard([draft])
        #expect(!FileManager.default.fileExists(atPath: draft.url.path))
        let promoted = try await store.promote([try await store.stageSceneImage(jpeg(width: 10, height: 10))])
        try await store.delete(relativePaths: Set(promoted + ["Images/missing.jpg"]))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: promoted[0]).path))
    }

    @Test func replacementOrderingKeepsOldUntilNewPromotionThenAllowsDeletion() async throws {
        let (store, root) = try makeStore(); defer { remove(root) }
        let old = try await store.promote([try await store.stageSceneImage(jpeg(width: 10, height: 10))])[0]
        let replacement = try await store.stageSceneImage(jpeg(width: 20, height: 20))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: old).path))
        let new = try await store.promote([replacement])[0]
        try await store.delete(relativePaths: [old])
        #expect(FileManager.default.fileExists(atPath: root.appending(path: new).path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: old).path))
    }

    @Test func orphanCleanupPreservesReferencedAndRecentAndRemovesStaleOwnedFiles() async throws {
        let (store, root) = try makeStore(); defer { remove(root) }
        let paths = try await store.promote([
            try await store.stageSceneImage(jpeg(width: 10, height: 10)),
            try await store.stageSceneImage(jpeg(width: 11, height: 11)),
            try await store.stageSceneImage(jpeg(width: 12, height: 12))
        ])
        let stale = Date(timeIntervalSinceNow: -3600)
        try FileManager.default.setAttributes([.modificationDate: stale], ofItemAtPath: root.appending(path: paths[0]).path)
        try FileManager.default.setAttributes([.modificationDate: stale], ofItemAtPath: root.appending(path: paths[1]).path)
        let draft = try await store.stageSceneImage(jpeg(width: 13, height: 13))
        try FileManager.default.setAttributes([.modificationDate: stale], ofItemAtPath: draft.url.path)
        let outside = root.deletingLastPathComponent().appending(path: UUID().uuidString)
        try Data([7]).write(to: outside)
        try await store.cleanOrphans(referencedPaths: [paths[0]], olderThan: Date(timeIntervalSinceNow: -60))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: paths[0]).path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: paths[1]).path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: paths[2]).path))
        #expect(!FileManager.default.fileExists(atPath: draft.url.path))
        #expect(FileManager.default.fileExists(atPath: outside.path))
        try? FileManager.default.removeItem(at: outside)
    }

    @Test func rejectsAbsoluteTraversalAndForgedDraftPaths() async throws {
        let (store, root) = try makeStore(); defer { remove(root) }
        await #expect(throws: ImageStoreError.self) { try await store.delete(relativePaths: ["/tmp/file"]) }
        await #expect(throws: ImageStoreError.self) { try await store.delete(relativePaths: ["Images/../secret"]) }
        await #expect(throws: ImageStoreError.self) { try await store.cleanOrphans(referencedPaths: ["../secret"], olderThan: .now) }
        let forged = ImageStore.DraftImage(url: root.appending(path: "Images/evil.jpg"), relativeName: "evil.jpg")
        await #expect(throws: ImageStoreError.self) { try await store.promote([forged]) }
    }

    @Test func concurrentStagingIsIsolated() async throws {
        let (store, root) = try makeStore(); defer { remove(root) }
        let data = try jpeg(width: 10, height: 10)
        let drafts = try await withThrowingTaskGroup(of: ImageStore.DraftImage.self) { group in
            for _ in 0..<20 { group.addTask { try await store.stageSceneImage(data) } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(Set(drafts.map(\.relativeName)).count == 20)
        #expect(drafts.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
    }

    @Test func loadRejectsFinalFileSymlinkToExternalVictim() async throws {
        let (store, root) = try makeStore(); defer { remove(root) }
        let victim = root.deletingLastPathComponent().appending(path: UUID().uuidString)
        try Data([1, 2, 3]).write(to: victim); defer { remove(victim) }
        let link = root.appending(path: "Images/link.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: victim)
        #expect(await store.loadImage(relativePath: "Images/link.jpg") == nil)
    }

    @Test func loadRejectsPostInitImagesDirectoryReplacement() async throws {
        let (store, root) = try makeStore(); defer { remove(root) }
        let images = root.appending(path: "Images")
        try FileManager.default.removeItem(at: images)
        let outside = root.deletingLastPathComponent().appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true); defer { remove(outside) }
        try Data([9, 8, 7]).write(to: outside.appending(path: "file.jpg"))
        try FileManager.default.createSymbolicLink(at: images, withDestinationURL: outside)
        #expect(await store.loadImage(relativePath: "Images/file.jpg") == nil)
    }

    @Test func cleanupBacklogSurvivesStoreRecreationAndRetriesOnlyFiles() async throws {
        let (store, root) = try makeStore(); defer { remove(root) }
        let path = try await store.promote([try await store.stageSceneImage(jpeg(width: 10, height: 10))])[0]
        try await store.enqueueCleanup(relativePaths: [path])
        let reopened = try ImageStore(rootDirectory: root)
        #expect(await reopened.hasPendingCleanup())
        try await reopened.retryPendingCleanup()
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: path).path))
        #expect(await reopened.hasPendingCleanup() == false)
    }

	@Test func pendingCaptureJournalSurvivesRelaunchAndCleansPromotedFiles() async throws {
		let (store, root) = try makeStore(); defer { remove(root) }
		let sceneID = UUID()
		let draft = try await store.stageSceneImage(jpeg(width: 20, height: 10))
		try await store.prepareCaptureCommit(sceneID: sceneID, drafts: [draft])
		_ = try await store.promote([draft])

		let reopened = try ImageStore(rootDirectory: root)
		let record = try #require(try await reopened.pendingCaptureCommit())
		#expect(record.sceneID == sceneID)
		#expect(record.draftNames == [draft.relativeName])
		try await reopened.discardFiles(for: record)
		try await reopened.clearPendingCaptureCommit()

		#expect(try await reopened.pendingCaptureCommit() == nil)
		#expect(!FileManager.default.fileExists(atPath: root.appending(path: "Images/\(draft.relativeName)").path))
	}

	@Test func reconcileToDraftsRepairsMixedPartialPromotionRollback() async throws {
		let (store, root) = try makeStore(); defer { remove(root) }
		let a = try await store.stageSceneImage(jpeg(width: 20, height: 10))
		let b = try await store.stageSceneImage(jpeg(width: 21, height: 11))
		_ = try await store.promote([a, b])
		try FileManager.default.moveItem(
			at: root.appending(path: "Images/\(a.relativeName)"),
			to: a.url
		)

		try await store.reconcileToDrafts([a, b])

		#expect(FileManager.default.fileExists(atPath: a.url.path))
		#expect(FileManager.default.fileExists(atPath: b.url.path))
		#expect(!FileManager.default.fileExists(atPath: root.appending(path: "Images/\(a.relativeName)").path))
		#expect(!FileManager.default.fileExists(atPath: root.appending(path: "Images/\(b.relativeName)").path))
	}

    @Test func thumbnailDownsamplesLargeSourceToRequestedPixelBound() async throws {
        let cache = SceneThumbnailCache(maximumCost: 32 * 1_024 * 1_024)
        let asset = SceneImageAsset(data: try jpeg(width: 3072, height: 1800), revision: 1)
        let thumbnail = try #require(await cache.thumbnail(path: "large", asset: asset, maxPixelSize: 320))
        #expect(max(thumbnail.image.cgImage?.width ?? 0, thumbnail.image.cgImage?.height ?? 0) <= 320)
    }
}

private func makeStore() throws -> (ImageStore, URL) {
    let root = temporaryRoot()
    return (try ImageStore(rootDirectory: root), root)
}

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
}

private func remove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

private func jpeg(width: Int, height: Int, orientation: Int = 1, noisy: Bool = false) throws -> Data {
    let image = noisy ? texturedImage(width: width, height: height) : solidImage(width: width, height: height)
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation, kCGImageDestinationLossyCompressionQuality: 0.98] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    return data as Data
}

private func solidImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func alphaImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.clear(CGRect(x: 0, y: 0, width: width, height: height)); context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5)); context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
    return context.makeImage()!
}

private func texturedImage(width: Int, height: Int) -> CGImage {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for index in 0..<(width * height) {
        let value = UInt32(truncatingIfNeeded: index &* 1_664_525 &+ 1_013_904_223)
        pixels[index * 4] = UInt8(truncatingIfNeeded: value >> 16)
        pixels[index * 4 + 1] = UInt8(truncatingIfNeeded: value >> 8)
        pixels[index * 4 + 2] = UInt8(truncatingIfNeeded: value)
    }
    let data = Data(pixels) as CFData
    let provider = CGDataProvider(data: data)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

private func alphaValue(_ image: CGImage, x: Int, y: Int) -> UInt8 {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.translateBy(x: -CGFloat(x), y: -CGFloat(y))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return pixel[3]
}

private func imageProperties(_ url: URL) throws -> (width: Int, height: Int, orientation: Int) {
    let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
    let values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
    return (values[kCGImagePropertyPixelWidth] as! Int, values[kCGImagePropertyPixelHeight] as! Int, values[kCGImagePropertyOrientation] as? Int ?? 1)
}
