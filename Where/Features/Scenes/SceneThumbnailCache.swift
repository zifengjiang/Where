import Foundation
import ImageIO
import UIKit

struct SceneImageAsset: Sendable {
    let data: Data
    let revision: UInt64
}

/// UIImage instances created from immutable encoded data are never mutated after crossing the actor boundary.
struct SceneThumbnail: @unchecked Sendable {
    let image: UIImage
    let decodedByteCost: Int
    init(image: UIImage, decodedByteCost: Int? = nil) {
        self.image = image
        let pixels = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
        self.decodedByteCost = decodedByteCost ?? pixels
    }
}

actor SceneThumbnailCache {
    static let shared = SceneThumbnailCache()
    struct Key: Hashable, Sendable { let path: String; let revision: UInt64; let maxPixelSize: Int }
    private let maximumCost: Int
    private let maximumCount: Int
    private var totalCost = 0
    private var values: [Key: SceneThumbnail] = [:]
    private var recency: [Key] = []
    private let decoder: @Sendable (Data, Int) -> SceneThumbnail?
    init(maximumCost: Int = 32 * 1_024 * 1_024, maximumCount: Int = 64, decoder: @escaping @Sendable (Data, Int) -> SceneThumbnail? = SceneThumbnailCache.decode) {
        self.maximumCost = max(1, maximumCost); self.maximumCount = max(1, maximumCount); self.decoder = decoder
    }
    func thumbnail(path: String, asset: SceneImageAsset, maxPixelSize: Int = 640) -> SceneThumbnail? {
        let bound = max(1, maxPixelSize)
        let key = Key(path: path, revision: asset.revision, maxPixelSize: bound)
        if let value = values[key] { touch(key); return value }
        guard let value = decoder(asset.data, bound) else { return nil }
        values[key] = value; totalCost += value.decodedByteCost; touch(key)
        while (values.count > maximumCount || totalCost > maximumCost), let oldest = recency.first {
            recency.removeFirst()
            if let removed = values.removeValue(forKey: oldest) { totalCost -= removed.decodedByteCost }
        }
        return value
    }
    private func touch(_ key: Key) { recency.removeAll { $0 == key }; recency.append(key) }
    nonisolated private static func decode(data: Data, maxPixelSize: Int) -> SceneThumbnail? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return SceneThumbnail(image: UIImage(cgImage: image), decodedByteCost: image.bytesPerRow * image.height)
    }
}
