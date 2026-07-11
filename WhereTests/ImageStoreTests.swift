import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Where

struct ImageStoreTests {
    @Test func createsDraftDirectoriesAndUniqueDrafts() async throws {
        let (store, root) = try makeStore()
        let data = try jpeg(width: 20, height: 10)
        let first = try await store.stageSceneImage(data)
        let second = try await store.stageSceneImage(data)
        #expect(first.url.deletingLastPathComponent().standardizedFileURL.path == root.appending(path: "Drafts").standardizedFileURL.path)
        #expect(first.relativeName != second.relativeName)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Images").path))
    }

    @Test func sceneJPEGNormalizesOrientationAndCapsLongestEdge() async throws {
        let (store, _) = try makeStore()
        let draft = try await store.stageSceneImage(jpeg(width: 4000, height: 2000, orientation: 6))
        let properties = try imageProperties(draft.url)
        #expect(draft.url.pathExtension == "jpg")
        #expect(properties.width == 1536)
        #expect(properties.height == 3072)
        #expect(properties.orientation == 1)
    }

    @Test func appearanceOriginalIsCompressedAndCapped() async throws {
        let (store, _) = try makeStore()
        let draft = try await store.stageAppearanceOriginal(jpeg(width: 2400, height: 1200))
        let properties = try imageProperties(draft.url)
        #expect(properties.width == 1600)
        #expect(properties.height == 800)
        #expect((try Data(contentsOf: draft.url)).count < (try jpeg(width: 2400, height: 1200, noisy: true)).count)
    }

    @Test func cutoutPersistsPNGWithAlpha() async throws {
        let (store, _) = try makeStore()
        let draft = try await store.stageCutout(alphaImage(width: 32, height: 24))
        let source = CGImageSourceCreateWithURL(draft.url as CFURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        #expect(draft.url.pathExtension == "png")
        #expect(image.width == 32 && image.height == 24)
        #expect(image.alphaInfo != .none && image.alphaInfo != .noneSkipFirst && image.alphaInfo != .noneSkipLast)
    }

    @Test func promoteMovesDraftsInInputOrderAndNeverOverwrites() async throws {
        let (store, root) = try makeStore()
        let a = try await store.stageSceneImage(jpeg(width: 11, height: 9))
        let b = try await store.stageSceneImage(jpeg(width: 12, height: 8))
        let paths = try await store.promote([b, a])
        #expect(paths == ["Images/\(b.relativeName)", "Images/\(a.relativeName)"])
        #expect(!FileManager.default.fileExists(atPath: a.url.path))
        #expect(paths.allSatisfy { FileManager.default.fileExists(atPath: root.appending(path: $0).path) })
        let forged = DraftImage(url: root.appending(path: "Drafts").appending(path: b.relativeName), relativeName: b.relativeName)
        try Data([1]).write(to: forged.url)
        await #expect(throws: ImageStoreError.self) { try await store.promote([forged]) }
        #expect((try Data(contentsOf: root.appending(path: paths[0]))) != Data([1]))

        let rollback = try await store.stageSceneImage(jpeg(width: 13, height: 7))
        await #expect(throws: ImageStoreError.self) { try await store.promote([rollback, forged]) }
        #expect(FileManager.default.fileExists(atPath: rollback.url.path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Images/\(rollback.relativeName)").path))
    }

    @Test func discardIsIdempotentAndDeleteIgnoresMissing() async throws {
        let (store, root) = try makeStore()
        let draft = try await store.stageSceneImage(jpeg(width: 10, height: 10))
        await store.discard([draft]); await store.discard([draft])
        #expect(!FileManager.default.fileExists(atPath: draft.url.path))
        let promoted = try await store.promote([try await store.stageSceneImage(jpeg(width: 10, height: 10))])
        try await store.delete(relativePaths: Set(promoted + ["Images/missing.jpg"]))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: promoted[0]).path))
    }

    @Test func replacementOrderingKeepsOldUntilNewPromotionThenAllowsDeletion() async throws {
        let (store, root) = try makeStore()
        let old = try await store.promote([try await store.stageSceneImage(jpeg(width: 10, height: 10))])[0]
        let replacement = try await store.stageSceneImage(jpeg(width: 20, height: 20))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: old).path))
        let new = try await store.promote([replacement])[0]
        try await store.delete(relativePaths: [old])
        #expect(FileManager.default.fileExists(atPath: root.appending(path: new).path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: old).path))
    }

    @Test func orphanCleanupPreservesReferencedAndRecentAndRemovesStaleOwnedFiles() async throws {
        let (store, root) = try makeStore()
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
        let (store, root) = try makeStore()
        await #expect(throws: ImageStoreError.self) { try await store.delete(relativePaths: ["/tmp/file"]) }
        await #expect(throws: ImageStoreError.self) { try await store.delete(relativePaths: ["Images/../secret"]) }
        await #expect(throws: ImageStoreError.self) { try await store.cleanOrphans(referencedPaths: ["../secret"], olderThan: .now) }
        let forged = DraftImage(url: root.appending(path: "Images/evil.jpg"), relativeName: "evil.jpg")
        await #expect(throws: ImageStoreError.self) { try await store.promote([forged]) }
    }

    @Test func concurrentStagingIsIsolated() async throws {
        let (store, _) = try makeStore()
        let data = try jpeg(width: 10, height: 10)
        let drafts = try await withThrowingTaskGroup(of: DraftImage.self) { group in
            for _ in 0..<20 { group.addTask { try await store.stageSceneImage(data) } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(Set(drafts.map(\.relativeName)).count == 20)
        #expect(drafts.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
    }
}

private func makeStore() throws -> (ImageStore, URL) {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    return (try ImageStore(rootDirectory: root), root)
}

private func jpeg(width: Int, height: Int, orientation: Int = 1, noisy: Bool = false) throws -> Data {
    let image = noisy ? alphaImage(width: width, height: height) : solidImage(width: width, height: height)
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

private func imageProperties(_ url: URL) throws -> (width: Int, height: Int, orientation: Int) {
    let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
    let values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
    return (values[kCGImagePropertyPixelWidth] as! Int, values[kCGImagePropertyPixelHeight] as! Int, values[kCGImagePropertyOrientation] as? Int ?? 1)
}
