import CoreGraphics

struct AspectFitGeometry: Equatable {
    let imageSize: CGSize
    let containerSize: CGSize

    /// Invalid, non-finite, or non-positive dimensions produce `.zero`.
    var imageRect: CGRect {
        guard imageSize.hasValidDimensions, containerSize.hasValidDimensions else { return .zero }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        guard scale.isFinite, scale > 0 else { return .zero }

        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    /// Boundaries are inclusive. Points in aspect-fit letterboxing or with non-finite values are rejected.
    func normalizedPoint(for viewPoint: CGPoint) -> CGPoint? {
        let rect = imageRect
        guard rect.width > 0, rect.height > 0,
              viewPoint.x.isFinite, viewPoint.y.isFinite,
              viewPoint.x >= rect.minX, viewPoint.x <= rect.maxX,
              viewPoint.y >= rect.minY, viewPoint.y <= rect.maxY else { return nil }

        return CGPoint(
            x: (viewPoint.x - rect.minX) / rect.width,
            y: (viewPoint.y - rect.minY) / rect.height
        )
    }

    /// Finite normalized values are clamped to `0...1`. Invalid geometry or non-finite values produce `.zero`.
    func viewPoint(for normalizedPoint: CGPoint) -> CGPoint {
        let rect = imageRect
        guard rect.width > 0, rect.height > 0,
              normalizedPoint.x.isFinite, normalizedPoint.y.isFinite else { return .zero }

        let x = min(max(normalizedPoint.x, 0), 1)
        let y = min(max(normalizedPoint.y, 0), 1)
        return CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }
}

private extension CGSize {
    var hasValidDimensions: Bool {
        width.isFinite && height.isFinite && width > 0 && height > 0
    }
}
