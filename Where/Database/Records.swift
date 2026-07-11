import Foundation
import GRDB

struct SceneRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "scene"

    var id: String
    var name: String
    var imagePath: String
    var createdAt: Date
    var updatedAt: Date
}

struct ItemRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "item"

    var id: String
    var sceneID: String
    var name: String
    var locationNote: String?
    var appearanceOriginalImagePath: String?
    var appearanceCutoutImagePath: String?
    var note: String?
    var normalizedX: Double
    var normalizedY: Double
    var createdAt: Date
    var updatedAt: Date
}

struct ItemAliasRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "itemAlias"

    var id: String
    var itemID: String
    var value: String
    var normalizedValue: String
    var createdAt: Date
}

struct TagRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "tag"

    var id: String
    var name: String
    var normalizedName: String
    var createdAt: Date
    var updatedAt: Date
}

struct ItemTagRecord: Codable, FetchableRecord, PersistableRecord, TableRecord {
    static let databaseTableName = "itemTag"

    var itemID: String
    var tagID: String
    var createdAt: Date
}
