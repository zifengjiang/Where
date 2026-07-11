import CoreGraphics
import CoreText
import UIKit

struct SilhouetteLine: Sendable, Equatable {
    let text: String
    let rect: CGRect
}

/// `CGPath` is an immutable Core Foundation value. The initializer stores a copy,
/// so sharing this result across actors cannot expose mutable path state.
struct SilhouetteTextLayoutResult: @unchecked Sendable {
    let path: CGPath
    let lines: [SilhouetteLine]
    let overflowed: Bool
    let usesFallbackCard: Bool

    init(path: CGPath, lines: [SilhouetteLine], overflowed: Bool, usesFallbackCard: Bool) {
        self.path = path.copy()!
        self.lines = lines
        self.overflowed = overflowed
        self.usesFallbackCard = usesFallbackCard
    }
}

struct SilhouetteTextMetrics: Sendable, Equatable {
    let fontSize: CGFloat
    let lineHeight: CGFloat
}

enum SilhouetteTextLayout {
    private static let maximumGridSide = 160
    private static let alphaThreshold: UInt8 = 96

    static func metrics(sizeCategory: UIContentSizeCategory) -> SilhouetteTextMetrics {
        let traits = UITraitCollection(preferredContentSizeCategory: sizeCategory)
        let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
        return SilhouetteTextMetrics(fontSize: font.pointSize, lineHeight: font.lineHeight)
    }

    static func fallbackLayout(text: String, canvasSize: CGSize, fontSize: CGFloat, lineHeight: CGFloat) -> SilhouetteTextLayoutResult {
        fallback(text: text, canvasSize: canvasSize, fontSize: fontSize, lineHeight: lineHeight)
    }

    static func layout(
        text: String,
        alphaImage: CGImage,
        canvasSize: CGSize,
        fontSize: CGFloat,
        lineHeight requestedLineHeight: CGFloat? = nil,
        sizeCategory: UIContentSizeCategory = .large
    ) -> SilhouetteTextLayoutResult {
        // The synchronous compatibility entry point is used by callers that do not
        // own cancellable background work.
        try! cancellableLayout(text: text, alphaImage: alphaImage, canvasSize: canvasSize, fontSize: fontSize,
                               lineHeight: requestedLineHeight, sizeCategory: sizeCategory, checkCancellation: {})
    }

    static func cancellableLayout(
        text: String,
        alphaImage: CGImage,
        canvasSize: CGSize,
        fontSize: CGFloat,
        lineHeight requestedLineHeight: CGFloat? = nil,
        sizeCategory: UIContentSizeCategory = .large,
        checkCancellation: () throws -> Void = { try Task.checkCancellation() }
    ) throws -> SilhouetteTextLayoutResult {
        try checkCancellation()
        let resolvedLineHeight = requestedLineHeight ?? fontSize * 1.25
        guard canvasSize.width > 0, canvasSize.height > 0 else { return fallback(text: text, canvasSize: canvasSize, fontSize: fontSize, lineHeight: resolvedLineHeight) }
        let grid = try alphaGrid(from: alphaImage, checkCancellation: checkCancellation)
        guard let component = try largestComponent(in: grid, checkCancellation: checkCancellation), component.count >= 4 else {
            return fallback(text: text, canvasSize: canvasSize, fontSize: fontSize, lineHeight: resolvedLineHeight)
        }

        let sx = canvasSize.width / CGFloat(grid.width), sy = canvasSize.height / CGFloat(grid.height)
        let inset = max(4, fontSize * 0.6)
        let spans = componentSpans(component: component, gridWidth: grid.width)
        let bounds = componentBounds(component, width: grid.width, sx: sx, sy: sy)
        var maxUsableWidth: CGFloat = 0
        for rowSpans in spans.values {
            try checkCancellation()
            for span in rowSpans {
                let pixelWidth = span.upperBound - span.lowerBound + 1
                maxUsableWidth = max(maxUsableWidth, CGFloat(pixelWidth) * sx - inset * 2)
            }
        }
        let accessibilityFactor: CGFloat = sizeCategory.isAccessibilityCategory ? 6.2 : 3.2
        let usableArea = CGFloat(component.count) * sx * sy
        guard maxUsableWidth >= fontSize * accessibilityFactor, usableArea >= fontSize * fontSize * 10 else {
            return fallback(text: text, canvasSize: canvasSize, fontSize: fontSize, lineHeight: resolvedLineHeight, boundingBox: bounds)
        }

        let path = CGMutablePath()
        for y in spans.keys.sorted() {
            try checkCancellation()
            for span in spans[y]! {
                let rect = CGRect(x: CGFloat(span.lowerBound) * sx + inset,
                                  y: CGFloat(y) * sy,
                                  width: CGFloat(span.upperBound - span.lowerBound + 1) * sx - inset * 2,
                                  height: sy)
                if rect.width > 0, rect.height > 0 { path.addRect(rect) }
            }
        }

        let lineHeight = resolvedLineHeight
        let rows = try horizontalRows(spans: spans, sx: sx, sy: sy, inset: inset, lineHeight: lineHeight, checkCancellation: checkCancellation)
        let font = CTFontCreateWithName("-apple-system" as CFString, fontSize, nil)
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var index = 0
        var lines: [SilhouetteLine] = []
        for row in rows where index < words.count {
            try checkCancellation()
            var candidate = words[index]
            var accepted = candidate
            var next = index + 1
            while next < words.count {
                candidate += " " + words[next]
                if width(of: candidate, font: font) > row.width { break }
                accepted = candidate
                next += 1
            }
            guard width(of: accepted, font: font) <= row.width else { continue }
            let measured = min(row.width, width(of: accepted, font: font))
            lines.append(SilhouetteLine(text: accepted, rect: CGRect(x: row.minX + 0.5, y: row.midY - lineHeight / 2, width: max(0, measured - 1), height: lineHeight)))
            index = next
        }
        return SilhouetteTextLayoutResult(path: path.copy()!, lines: lines, overflowed: index < words.count, usesFallbackCard: false)
    }

    fileprivate struct Grid { let width: Int; let height: Int; let pixels: [UInt8] }

    private static func alphaGrid(from image: CGImage, checkCancellation: () throws -> Void) throws -> Grid {
        let scale = min(1, CGFloat(maximumGridSide) / CGFloat(max(image.width, image.height)))
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let bytesPerRow = width * 4
        rgba.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setBlendMode(.copy)
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var alpha = [UInt8](repeating: 0, count: width * height)
        for index in alpha.indices {
            if index.isMultiple(of: 1024) { try checkCancellation() }
            alpha[index] = rgba[index * 4 + 3]
        }
        return Grid(width: width, height: height, pixels: alpha)
    }

    private static func largestComponent(in grid: Grid, checkCancellation: () throws -> Void) throws -> [Int]? {
        var visited = [Bool](repeating: false, count: grid.pixels.count), best: [Int] = []
        for start in grid.pixels.indices where !visited[start] && grid.pixels[start] >= alphaThreshold {
            try checkCancellation()
            visited[start] = true; var queue = [start], cursor = 0
            while cursor < queue.count {
                if cursor.isMultiple(of: 256) { try checkCancellation() }
                let value = queue[cursor]; cursor += 1
                let x = value % grid.width, y = value / grid.width
                for (nx, ny) in [(x-1,y), (x+1,y), (x,y-1), (x,y+1)] where nx >= 0 && ny >= 0 && nx < grid.width && ny < grid.height {
                    let next = ny * grid.width + nx
                    if !visited[next] && grid.pixels[next] >= alphaThreshold { visited[next] = true; queue.append(next) }
                }
            }
            if queue.count > best.count { best = queue }
        }
        return best.isEmpty ? nil : best
    }

    private static func componentSpans(component: [Int], gridWidth: Int) -> [Int: [ClosedRange<Int>]] {
        let grouped = Dictionary(grouping: component, by: { $0 / gridWidth })
        var result: [Int: [ClosedRange<Int>]] = [:]
        for (y, values) in grouped {
            let xs = values.map { $0 % gridWidth }.sorted()
            var spans: [ClosedRange<Int>] = [], start = xs[0], previous = xs[0]
            for x in xs.dropFirst() {
                if x > previous + 1 { spans.append(start...previous); start = x }
                previous = x
            }
            spans.append(start...previous); result[y] = spans
        }
        return result
    }

    private static func horizontalRows(spans: [Int: [ClosedRange<Int>]], sx: CGFloat, sy: CGFloat, inset: CGFloat, lineHeight: CGFloat, checkCancellation: () throws -> Void) throws -> [CGRect] {
        guard let minGridY = spans.keys.min(), let maxGridY = spans.keys.max() else { return [] }
        var result: [CGRect] = [], y = CGFloat(minGridY) * sy + inset
        while y + lineHeight <= CGFloat(maxGridY + 1) * sy - inset {
            try checkCancellation()
            let firstRow = max(minGridY, Int(floor(y / sy)))
            let lastRow = min(maxGridY, Int(floor((y + lineHeight - 0.001) / sy)))
            var safe = spans[firstRow] ?? []
            if lastRow > firstRow {
                for row in (firstRow + 1)...lastRow { safe = intersect(safe, spans[row] ?? []) }
            }
            if let widest = safe.max(by: { $0.count < $1.count }) {
                let rect = CGRect(x: CGFloat(widest.lowerBound) * sx + inset, y: y,
                                  width: CGFloat(widest.count) * sx - inset * 2, height: lineHeight)
                if rect.width > 0 { result.append(rect) }
            }
            y += lineHeight
        }
        return result
    }

    private static func intersect(_ lhs: [ClosedRange<Int>], _ rhs: [ClosedRange<Int>]) -> [ClosedRange<Int>] {
        var result: [ClosedRange<Int>] = []
        for a in lhs { for b in rhs {
            let lower = max(a.lowerBound, b.lowerBound), upper = min(a.upperBound, b.upperBound)
            if lower <= upper { result.append(lower...upper) }
        } }
        return result
    }

    private static func componentBounds(_ component: [Int], width: Int, sx: CGFloat, sy: CGFloat) -> CGRect {
        let xs = component.map { $0 % width }, ys = component.map { $0 / width }
        return CGRect(x: CGFloat(xs.min()!) * sx, y: CGFloat(ys.min()!) * sy,
                      width: CGFloat(xs.max()! - xs.min()! + 1) * sx, height: CGFloat(ys.max()! - ys.min()! + 1) * sy)
    }

    private static func width(of string: String, font: CTFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private static func fallback(text: String, canvasSize: CGSize, fontSize: CGFloat, lineHeight: CGFloat, boundingBox: CGRect? = nil) -> SilhouetteTextLayoutResult {
        let box = (boundingBox ?? CGRect(origin: .zero, size: canvasSize)).insetBy(dx: 4, dy: 4)
        let path = CGPath(roundedRect: box, cornerWidth: min(18, box.width / 5), cornerHeight: min(18, box.height / 5), transform: nil)
        let content = box.insetBy(dx: max(8, fontSize * 0.7), dy: max(8, fontSize * 0.7))
        let font = CTFontCreateWithName("-apple-system" as CFString, fontSize, nil)
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var lines: [SilhouetteLine] = [], index = 0, y = content.minY
        while index < words.count, y + lineHeight <= content.maxY {
            var accepted = words[index], next = index + 1
            while next < words.count {
                let candidate = accepted + " " + words[next]
                if width(of: candidate, font: font) > content.width { break }
                accepted = candidate; next += 1
            }
            if width(of: accepted, font: font) > content.width { break }
            lines.append(SilhouetteLine(text: accepted, rect: CGRect(x: content.minX, y: y, width: min(content.width, width(of: accepted, font: font)), height: lineHeight)))
            index = next; y += lineHeight
        }
        return SilhouetteTextLayoutResult(path: path, lines: lines, overflowed: index < words.count, usesFallbackCard: true)
    }
}
