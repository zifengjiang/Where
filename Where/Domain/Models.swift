import Foundation

struct ItemDraft: Sendable, Equatable {
    let id: UUID
    let name: String
    let locationNote: String?
    let note: String?
    let normalizedX: Double
    let normalizedY: Double
    let aliases: [String]
    let tags: [String]
    let appearanceOriginalImagePath: String?
    let appearanceCutoutImagePath: String?
}

struct SceneDraft: Sendable, Equatable {
    let id: UUID
    let name: String
    let imagePath: String
    let items: [ItemDraft]
}

struct ItemSummary: Sendable, Equatable {
    let id: UUID
    let sceneID: UUID
    let sceneName: String
    let sceneImagePath: String
    let name: String
    let locationNote: String?
    let note: String?
    let normalizedX: Double
    let normalizedY: Double
    let aliases: [String]
    let tags: [String]
    let appearanceOriginalImagePath: String?
    let appearanceCutoutImagePath: String?
    let createdAt: Date
    let updatedAt: Date
}

struct SceneSummary: Sendable, Equatable {
    let id: UUID
    let name: String
    let imagePath: String
    let itemCount: Int
    let createdAt: Date
    let updatedAt: Date
}

struct DeletedImagePaths: Sendable, Equatable {
    let original: String?
    let cutout: String?
}

struct DeletedSceneImagePaths: Sendable, Equatable {
    let scene: String
    let items: [DeletedImagePaths]
}
