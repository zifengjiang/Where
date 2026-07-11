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
}

enum SilhouetteTextLayout {
    private static let maximumGridSide = 160
    private static let alphaThreshold: UInt8 = 96

    static func layout(
        text: String,
        alphaImage: CGImage,
        canvasSize: CGSize,
        fontSize: CGFloat,
        sizeCategory: UIContentSizeCategory = .large
    ) -> SilhouetteTextLayoutResult {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return fallback(text: text, canvasSize: canvasSize, fontSize: fontSize) }
        let grid = alphaGrid(from: alphaImage)
        guard let component = largestComponent(in: grid), component.count >= 4 else {
            return fallback(text: text, canvasSize: canvasSize, fontSize: fontSize)
        }

        let sx = canvasSize.width / CGFloat(grid.width), sy = canvasSize.height / CGFloat(grid.height)
        let inset = max(4, fontSize * 0.6)
        var spans: [(y: Int, minX: Int, maxX: Int)] = []
        let grouped = Dictionary(grouping: component, by: { $0 / grid.width })
        for y in grouped.keys.sorted() {
            let xs = grouped[y]!.map { $0 % grid.width }
            if let low = xs.min(), let high = xs.max() { spans.append((y, low, high)) }
        }
        let bounds = componentBounds(component, width: grid.width, sx: sx, sy: sy)
        let maxUsableWidth = spans.map { CGFloat($0.maxX - $0.minX + 1) * sx - inset * 2 }.max() ?? 0
        let accessibilityFactor: CGFloat = sizeCategory.isAccessibilityCategory ? 6.2 : 3.2
        let usableArea = CGFloat(component.count) * sx * sy
        guard maxUsableWidth >= fontSize * accessibilityFactor, usableArea >= fontSize * fontSize * 10 else {
            return fallback(text: text, canvasSize: canvasSize, fontSize: fontSize, boundingBox: bounds)
        }

        let path = CGMutablePath()
        for span in spans {
            let rect = CGRect(x: CGFloat(span.minX) * sx + inset,
                              y: CGFloat(span.y) * sy,
                              width: CGFloat(span.maxX - span.minX + 1) * sx - inset * 2,
                              height: sy)
            if rect.width > 0, rect.height > 0 { path.addRect(rect) }
        }

        let lineHeight = fontSize * 1.25
        let rows = horizontalRows(component: component, gridWidth: grid.width, sx: sx, sy: sy, inset: inset, lineHeight: lineHeight)
        let font = CTFontCreateWithName("-apple-system" as CFString, fontSize, nil)
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var index = 0
        var lines: [SilhouetteLine] = []
        for row in rows where index < words.count {
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

    private static func alphaGrid(from image: CGImage) -> Grid {
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
        for index in alpha.indices { alpha[index] = rgba[index * 4 + 3] }
        return Grid(width: width, height: height, pixels: alpha)
    }

    private static func largestComponent(in grid: Grid) -> [Int]? {
        var visited = [Bool](repeating: false, count: grid.pixels.count), best: [Int] = []
        for start in grid.pixels.indices where !visited[start] && grid.pixels[start] >= alphaThreshold {
            visited[start] = true; var queue = [start], cursor = 0
            while cursor < queue.count {
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

    private static func horizontalRows(component: [Int], gridWidth: Int, sx: CGFloat, sy: CGFloat, inset: CGFloat, lineHeight: CGFloat) -> [CGRect] {
        let set = Set(component); let maxY = (component.max() ?? 0) / gridWidth
        var result: [CGRect] = [], y = inset
        while y + lineHeight <= CGFloat(maxY + 1) * sy - inset {
            let gridY = min(maxY, max(0, Int((y + lineHeight / 2) / sy)))
            let xs = set.filter { $0 / gridWidth == gridY }.map { $0 % gridWidth }
            if let lo = xs.min(), let hi = xs.max() {
                let rect = CGRect(x: CGFloat(lo) * sx + inset, y: y, width: CGFloat(hi - lo + 1) * sx - inset * 2, height: lineHeight)
                if rect.width > 0 { result.append(rect) }
            }
            y += lineHeight
        }
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

    private static func fallback(text: String, canvasSize: CGSize, fontSize: CGFloat, boundingBox: CGRect? = nil) -> SilhouetteTextLayoutResult {
        let box = (boundingBox ?? CGRect(origin: .zero, size: canvasSize)).insetBy(dx: 4, dy: 4)
        let path = CGPath(roundedRect: box, cornerWidth: min(18, box.width / 5), cornerHeight: min(18, box.height / 5), transform: nil)
        let content = box.insetBy(dx: max(8, fontSize * 0.7), dy: max(8, fontSize * 0.7))
        let font = CTFontCreateWithName("-apple-system" as CFString, fontSize, nil)
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let lineHeight = fontSize * 1.25
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
