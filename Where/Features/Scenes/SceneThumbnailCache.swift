import Foundation
import UIKit

struct SceneImageAsset: Sendable {
    let data: Data
    let revision: UInt64
}

/// UIImage instances created from immutable encoded data are never mutated after crossing the actor boundary.
struct SceneThumbnail: @unchecked Sendable { let image: UIImage }

actor SceneThumbnailCache {
    static let shared = SceneThumbnailCache()
    struct Key: Hashable, Sendable { let path: String; let revision: UInt64 }
    private let capacity: Int
    private var values: [Key: SceneThumbnail] = [:]
    private var recency: [Key] = []
    private let decoder: @Sendable (Data) -> SceneThumbnail?
    init(capacity: Int = 24, decoder: @escaping @Sendable (Data) -> SceneThumbnail? = { data in UIImage(data: data).map(SceneThumbnail.init) }) {
        self.capacity = max(1, capacity); self.decoder = decoder
    }
    func thumbnail(path: String, asset: SceneImageAsset) -> SceneThumbnail? {
        let key = Key(path: path, revision: asset.revision)
        if let value = values[key] { touch(key); return value }
        guard let value = decoder(asset.data) else { return nil }
        values[key] = value; touch(key)
        while values.count > capacity, let oldest = recency.first { recency.removeFirst(); values[oldest] = nil }
        return value
    }
    private func touch(_ key: Key) { recency.removeAll { $0 == key }; recency.append(key) }
}
