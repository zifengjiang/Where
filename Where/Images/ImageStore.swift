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
	struct PendingCaptureCommit: Codable, Sendable, Equatable {
		let sceneID: UUID
		let draftNames: [String]
	}
    struct DraftImage: Sendable {
        let url: URL
        let relativeName: String
    }

    let rootDirectory: URL
    private let canonicalRootDirectory: URL
    private let draftsDirectory: URL
    private let imagesDirectory: URL
    private let fileManager = FileManager.default
    private var volatileCleanupPaths: Set<String> = []
    private var cleanupBacklogURL: URL { rootDirectory.appending(path: "PendingImageCleanup.json") }
	private var pendingCaptureCommitURL: URL { rootDirectory.appending(path: "PendingCaptureCommit.json") }

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

    /// Restores a just-promoted batch to Drafts when its database transaction fails.
    /// The all-or-nothing move lets the capture flow retain a retryable draft.
    func restorePromoted(_ drafts: [DraftImage]) async throws {
        try verifyOwnedStorage()
        for draft in drafts { try validate(draft) }
        var restored: [(draft: URL, final: URL)] = []
        do {
            for draft in drafts.reversed() {
                let final = imagesDirectory.appending(path: draft.relativeName)
                guard fileManager.fileExists(atPath: final.path) else {
                    throw ImageStoreError.unsafePath(draft.relativeName)
                }
                try verifyOwnedStorage()
                try fileManager.moveItem(at: final, to: draft.url)
                restored.append((draft.url, final))
            }
        } catch {
            var recoverableFinalPaths: [String] = []
            for move in restored.reversed() {
                do {
                    try verifyOwnedStorage()
                    try fileManager.moveItem(at: move.draft, to: move.final)
                } catch {
                    recoverableFinalPaths.append("Images/\(move.final.lastPathComponent)")
                }
            }
            if !recoverableFinalPaths.isEmpty {
                throw ImageStoreError.rollbackIncomplete(recoverableFinalPaths: recoverableFinalPaths)
            }
            throw error
        }
    }

	/// Reconciles an interrupted/partially rolled-back promotion into a fully retryable Drafts batch.
	func reconcileToDrafts(_ drafts: [DraftImage]) throws {
		try verifyOwnedStorage()
		for draft in drafts {
			try validate(draft)
			let final = imagesDirectory.appending(path: draft.relativeName)
			let hasDraft = fileManager.fileExists(atPath: draft.url.path)
			let hasFinal = fileManager.fileExists(atPath: final.path)
			switch (hasDraft, hasFinal) {
			case (true, true): try fileManager.removeItem(at: final)
			case (false, true): try fileManager.moveItem(at: final, to: draft.url)
			case (true, false): break
			case (false, false): throw ImageStoreError.unsafePath(draft.relativeName)
			}
		}
	}

    func discard(_ drafts: [DraftImage]) async {
        guard (try? verifyOwnedStorage()) != nil else { return }
        for draft in drafts {
            guard (try? validate(draft)) != nil else { continue }
            guard (try? verifyOwnedStorage()) != nil else { return }
            try? fileManager.removeItem(at: draft.url)
        }
    }

	func prepareCaptureCommit(sceneID: UUID, drafts: [DraftImage]) throws {
		try verifyOwnedStorage()
		for draft in drafts { try validate(draft) }
		let record = PendingCaptureCommit(sceneID: sceneID, draftNames: drafts.map(\.relativeName))
		try JSONEncoder().encode(record).write(to: pendingCaptureCommitURL, options: .atomic)
	}

	func pendingCaptureCommit() throws -> PendingCaptureCommit? {
		try verifyOwnedStorage()
		guard fileManager.fileExists(atPath: pendingCaptureCommitURL.path) else { return nil }
		let record = try JSONDecoder().decode(PendingCaptureCommit.self, from: Data(contentsOf: pendingCaptureCommitURL))
		for name in record.draftNames { try validateName(name) }
		return record
	}

	func clearPendingCaptureCommit() throws {
		try verifyOwnedStorage()
		if fileManager.fileExists(atPath: pendingCaptureCommitURL.path) {
			try fileManager.removeItem(at: pendingCaptureCommitURL)
		}
	}

	func discardFiles(for record: PendingCaptureCommit) async throws {
		try verifyOwnedStorage()
		for name in record.draftNames {
			try validateName(name)
			let draft = draftsDirectory.appending(path: name)
			if fileManager.fileExists(atPath: draft.path) { try fileManager.removeItem(at: draft) }
		}
		try await delete(relativePaths: Set(record.draftNames.map { "Images/\($0)" }))
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
        await loadImageAsset(relativePath: relativePath)?.data
    }

    func loadImageAsset(relativePath: String) async -> SceneImageAsset? {
        guard (try? verifyOwnedStorage()) != nil,
              let name = try? finalFilename(relativePath),
              let asset = try? readImageAsset(filename: name) else { return nil }
        return asset
    }

    private func readImageAsset(filename: String) throws -> SceneImageAsset {
        let directoryFD = imagesDirectory.path.withCString { open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard directoryFD >= 0 else { throw ImageStoreError.unsafeStorage(imagesDirectory.path) }
        defer { close(directoryFD) }

        let fileFD = filename.withCString { openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard fileFD >= 0 else { throw ImageStoreError.unsafePath(filename) }
        defer { close(fileFD) }

        var information = stat()
        guard fstat(fileFD, &information) == 0,
              information.st_mode & S_IFMT == S_IFREG,
              information.st_size >= 0,
              information.st_size <= Int64(Int.max) else { throw ImageStoreError.unsafePath(filename) }

        var data = Data(count: Int(information.st_size))
        var offset = 0
        while offset < data.count {
            let remaining = data.count - offset
            let count = data.withUnsafeMutableBytes { bytes in
                read(fileFD, bytes.baseAddress!.advanced(by: offset), remaining)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw ImageStoreError.unsafePath(filename)
            }
            guard count > 0 else { throw ImageStoreError.unsafePath(filename) }
            offset += count
        }
        let revision = UInt64(bitPattern: Int64(information.st_mtimespec.tv_sec))
            ^ UInt64(bitPattern: Int64(information.st_mtimespec.tv_nsec))
            ^ UInt64(information.st_size)
        return SceneImageAsset(data: data, revision: revision)
    }

    func cleanOrphans(referencedPaths: Set<String>, olderThan: Date) async throws {
        try verifyOwnedStorage()
        let referenced = Set(try referencedPaths.map { try finalURL($0).standardizedFileURL.path })
        try removeStaleFiles(in: imagesDirectory, olderThan: olderThan) { referenced.contains($0.standardizedFileURL.path) }
        try removeStaleFiles(in: draftsDirectory, olderThan: olderThan) { _ in false }
    }

    func enqueueCleanup(relativePaths: [String]) async throws {
        volatileCleanupPaths.formUnion(relativePaths)
        try verifyOwnedStorage()
        var paths = try pendingCleanupPaths()
        for path in volatileCleanupPaths { _ = try finalURL(path); paths.insert(path) }
        let data = try JSONEncoder().encode(paths.sorted())
        try data.write(to: cleanupBacklogURL, options: .atomic)
        volatileCleanupPaths.removeAll()
    }

    func hasPendingCleanup() async -> Bool { !volatileCleanupPaths.isEmpty || !((try? pendingCleanupPaths()) ?? []).isEmpty }

    func retryPendingCleanup() async throws {
        if !volatileCleanupPaths.isEmpty { try await enqueueCleanup(relativePaths: []) }
        let paths = try pendingCleanupPaths()
        guard !paths.isEmpty else { return }
        try await delete(relativePaths: paths)
        try? fileManager.removeItem(at: cleanupBacklogURL)
    }

    private func pendingCleanupPaths() throws -> Set<String> {
        try verifyOwnedStorage()
        guard fileManager.fileExists(atPath: cleanupBacklogURL.path) else { return [] }
        let values = try JSONDecoder().decode([String].self, from: Data(contentsOf: cleanupBacklogURL))
        for value in values { _ = try finalURL(value) }
        return Set(values)
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
		try validateName(name)
		let expected = draftsDirectory.appending(path: name).standardizedFileURL
		guard draft.url.standardizedFileURL == expected,
			  expected.deletingLastPathComponent() == draftsDirectory.standardizedFileURL else {
			throw ImageStoreError.unsafePath(draft.url.path)
		}
	}

	private func validateName(_ name: String) throws {
		guard !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent,
              !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else {
            throw ImageStoreError.unsafePath(name)
        }
    }

    private func finalURL(_ relativePath: String) throws -> URL {
        let filename = try finalFilename(relativePath)
        return imagesDirectory.appending(path: filename)
    }

    private func finalFilename(_ relativePath: String) throws -> String {
        guard !relativePath.hasPrefix("/"), !relativePath.contains("\\") else { throw ImageStoreError.unsafePath(relativePath) }
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "Images", !parts[1].isEmpty, parts[1] != ".", parts[1] != ".." else {
            throw ImageStoreError.unsafePath(relativePath)
        }
        return String(parts[1])
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
    func loadImageAsset(relativePath: String) async -> SceneImageAsset?
    func delete(relativePaths: [String]) async throws
    func enqueueCleanup(relativePaths: [String]) async throws
    func hasPendingCleanup() async -> Bool
    func retryPendingCleanup() async throws
}

extension SceneImageStoreProtocol {
    func loadImageAsset(relativePath: String) async -> SceneImageAsset? {
        await loadImage(relativePath: relativePath).map { SceneImageAsset(data: $0, revision: 0) }
    }
}

extension ImageStore: SceneImageStoreProtocol {
    func delete(relativePaths: [String]) async throws { try await delete(relativePaths: Set(relativePaths)) }
}
