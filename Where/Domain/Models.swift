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
