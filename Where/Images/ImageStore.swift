import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageStoreError: Error {
    case invalidImage
    case unsafePath(String)
    case unsafeStorage(String)
    case destinationExists(String)
    case encodingFailed
    case rollbackIncomplete(recoverableFinalPaths: [String])
}

actor ImageStore {
    struct DraftImage: Sendable {
        let url: URL
        let relativeName: String
    }

    let rootDirectory: URL
    private let canonicalRootDirectory: URL
    private let draftsDirectory: URL
    private let imagesDirectory: URL
    private let fileManager = FileManager.default

    init(rootDirectory: URL) throws {
        let root = rootDirectory.standardizedFileURL
        try Self.rejectSymlink(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.requireDirectory(at: root)
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let drafts = root.appending(path: "Drafts", directoryHint: .isDirectory)
        let images = root.appending(path: "Images", directoryHint: .isDirectory)
        try Self.rejectSymlink(at: drafts)
        try Self.rejectSymlink(at: images)
        try FileManager.default.createDirectory(at: drafts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Self.verifyOwnedDirectories(root: root, canonicalRoot: canonicalRoot, drafts: drafts, images: images)
        self.rootDirectory = root
        self.canonicalRootDirectory = canonicalRoot
        self.draftsDirectory = drafts
        self.imagesDirectory = images
    }

    func stageSceneImage(_ data: Data) async throws -> DraftImage {
        try await stage(data, longestEdge: 3072)
    }

    func stageAppearanceOriginal(_ data: Data) async throws -> DraftImage {
        try await stage(data, longestEdge: 1600)
    }

    func stageCutout(_ image: CGImage) async throws -> DraftImage {
        let encoded = try await Task.detached(priority: .userInitiated) {
            try Self.encode(image: image, type: UTType.png.identifier as CFString, properties: [:])
        }.value
        return try writeDraft(encoded, extension: "png")
    }

    func promote(_ drafts: [DraftImage]) async throws -> [String] {
        try verifyOwnedStorage()
        for draft in drafts { try validate(draft) }
        var moved: [(draft: URL, final: URL)] = []
        do {
            for draft in drafts {
                try verifyOwnedStorage()
                let final = imagesDirectory.appending(path: draft.relativeName)
                guard !fileManager.fileExists(atPath: final.path) else {
                    throw ImageStoreError.destinationExists(draft.relativeName)
                }
                try verifyOwnedStorage()
                try fileManager.moveItem(at: draft.url, to: final)
                moved.append((draft.url, final))
            }
        } catch {
            var recoverableFinalPaths: [String] = []
            for move in moved.reversed() {
                do {
                    try verifyOwnedStorage()
                    guard fileManager.fileExists(atPath: move.final.path) else { continue }
                    try verifyOwnedStorage()
                    try fileManager.moveItem(at: move.final, to: move.draft)
                } catch {
                    recoverableFinalPaths.append("Images/\(move.final.lastPathComponent)")
                }
            }
            if !recoverableFinalPaths.isEmpty {
                throw ImageStoreError.rollbackIncomplete(recoverableFinalPaths: recoverableFinalPaths)
            }
            throw error
        }
        return drafts.map { "Images/\($0.relativeName)" }
    }

    func discard(_ drafts: [DraftImage]) async {
        guard (try? verifyOwnedStorage()) != nil else { return }
        for draft in drafts {
            guard (try? validate(draft)) != nil else { continue }
            guard (try? verifyOwnedStorage()) != nil else { return }
            try? fileManager.removeItem(at: draft.url)
        }
    }

    func delete(relativePaths: Set<String>) async throws {
        try verifyOwnedStorage()
        let urls = try relativePaths.map(finalURL)
        for url in urls {
            try verifyOwnedStorage()
            guard fileManager.fileExists(atPath: url.path) else { continue }
            try verifyOwnedStorage()
            try fileManager.removeItem(at: url)
        }
    }

    func loadImage(relativePath: String) async -> Data? {
        guard let url = try? finalURL(relativePath) else { return nil }
        return await Task.detached(priority: .utility) { try? Data(contentsOf: url, options: .mappedIfSafe) }.value
    }

    func cleanOrphans(referencedPaths: Set<String>, olderThan: Date) async throws {
        try verifyOwnedStorage()
        let referenced = Set(try referencedPaths.map { try finalURL($0).standardizedFileURL.path })
        try removeStaleFiles(in: imagesDirectory, olderThan: olderThan) { referenced.contains($0.standardizedFileURL.path) }
        try removeStaleFiles(in: draftsDirectory, olderThan: olderThan) { _ in false }
    }

    private func stage(_ data: Data, longestEdge: Int) async throws -> DraftImage {
        let encoded = try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: longestEdge
                  ] as CFDictionary) else { throw ImageStoreError.invalidImage }
            return try Self.encode(
                image: image,
                type: UTType.jpeg.identifier as CFString,
                properties: [kCGImageDestinationLossyCompressionQuality: 0.78]
            )
        }.value
        return try writeDraft(encoded, extension: "jpg")
    }

    private func writeDraft(_ data: Data, extension ext: String) throws -> DraftImage {
        try verifyOwnedStorage()
        let name = "\(UUID().uuidString).\(ext)"
        let url = draftsDirectory.appending(path: name)
        try verifyOwnedStorage()
        try data.write(to: url, options: .withoutOverwriting)
        return DraftImage(url: url, relativeName: name)
    }

    nonisolated private static func encode(image: CGImage, type: CFString, properties: [CFString: Any]) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else { throw ImageStoreError.encodingFailed }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageStoreError.encodingFailed }
        return data as Data
    }

    private func validate(_ draft: DraftImage) throws {
        let name = draft.relativeName
        guard !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent,
              !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else {
            throw ImageStoreError.unsafePath(name)
        }
        let expected = draftsDirectory.appending(path: name).standardizedFileURL
        guard draft.url.standardizedFileURL == expected,
              expected.deletingLastPathComponent() == draftsDirectory.standardizedFileURL else {
            throw ImageStoreError.unsafePath(draft.url.path)
        }
    }

    private func finalURL(_ relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/"), !relativePath.contains("\\") else { throw ImageStoreError.unsafePath(relativePath) }
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "Images", !parts[1].isEmpty, parts[1] != ".", parts[1] != ".." else {
            throw ImageStoreError.unsafePath(relativePath)
        }
        let url = rootDirectory.appending(path: relativePath).standardizedFileURL
        guard url.deletingLastPathComponent() == imagesDirectory.standardizedFileURL else { throw ImageStoreError.unsafePath(relativePath) }
        return url
    }

    private func removeStaleFiles(in directory: URL, olderThan: Date, preserving: (URL) -> Bool) throws {
        try verifyOwnedStorage()
        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey], options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
        for url in urls {
            try verifyOwnedStorage()
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true, let modified = values.contentModificationDate,
                  modified < olderThan, !preserving(url) else { continue }
            try verifyOwnedStorage()
            try fileManager.removeItem(at: url)
        }
    }

    private func verifyOwnedStorage() throws {
        try Self.verifyOwnedDirectories(
            root: rootDirectory,
            canonicalRoot: canonicalRootDirectory,
            drafts: draftsDirectory,
            images: imagesDirectory
        )
    }

    nonisolated private static func verifyOwnedDirectories(root: URL, canonicalRoot: URL, drafts: URL, images: URL) throws {
        try rejectSymlink(at: root)
        try requireDirectory(at: root)
        guard root.resolvingSymlinksInPath().standardizedFileURL == canonicalRoot else {
            throw ImageStoreError.unsafeStorage(root.path)
        }
        for directory in [drafts, images] {
            try rejectSymlink(at: directory)
            try requireDirectory(at: directory)
            let resolved = directory.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.deletingLastPathComponent() == canonicalRoot,
                  resolved.path == canonicalRoot.appending(path: directory.lastPathComponent).path else {
                throw ImageStoreError.unsafeStorage(directory.path)
            }
        }
    }

    nonisolated private static func rejectSymlink(at url: URL) throws {
        var information = stat()
        let result = url.path.withCString { lstat($0, &information) }
        if result == -1 {
            guard errno == ENOENT else { throw ImageStoreError.unsafeStorage(url.path) }
            return
        }
        guard information.st_mode & S_IFMT != S_IFLNK else {
            throw ImageStoreError.unsafeStorage(url.path)
        }
    }

    nonisolated private static func requireDirectory(at url: URL) throws {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            throw ImageStoreError.unsafeStorage(url.path)
        }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw ImageStoreError.unsafeStorage(url.path)
        }
    }
}

protocol SceneImageStoreProtocol: Sendable {
    func loadImage(relativePath: String) async -> Data?
    func delete(relativePaths: [String]) async throws
}

extension ImageStore: SceneImageStoreProtocol {
    func delete(relativePaths: [String]) async throws { try await delete(relativePaths: Set(relativePaths)) }
}
