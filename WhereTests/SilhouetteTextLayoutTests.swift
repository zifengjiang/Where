import CoreGraphics
import Testing
import UIKit
@testable import Where

struct SilhouetteTextLayoutTests {
    @Test func rectangleInsetsPathAndKeepsLinesInOpaqueRegion() throws {
        let image = mask(width: 100, height: 80) { x, y in x >= 10 && x < 90 && y >= 8 && y < 72 ? 255 : 0 }
        let result = SilhouetteTextLayout.layout(text: "one two three four five six", alphaImage: image, canvasSize: CGSize(width: 200, height: 160), fontSize: 16)
        #expect(!result.usesFallbackCard)
        #expect(result.path.boundingBox.minX >= 24)
        #expect(result.path.boundingBox.maxX <= 176)
        #expect(result.lines.allSatisfy { result.path.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) })
    }

    @Test func circleProducesFragmentsInsideAcceptedOpaqueRegion() {
        let image = mask(width: 120, height: 120) { x, y in
            let dx = Double(x - 60), dy = Double(y - 60)
            return dx * dx + dy * dy <= 50 * 50 ? 255 : 0
        }
        let result = SilhouetteTextLayout.layout(text: String(repeating: "round words ", count: 20), alphaImage: image, canvasSize: CGSize(width: 240, height: 240), fontSize: 15)
        #expect(!result.usesFallbackCard)
        #expect(!result.lines.isEmpty)
        #expect(result.lines.allSatisfy { result.path.contains(CGPoint(x: $0.rect.minX, y: $0.rect.midY)) && result.path.contains(CGPoint(x: $0.rect.maxX, y: $0.rect.midY)) })
    }

    @Test func disconnectedIslandsRetainsLargestMeaningfulComponent() {
        let image = mask(width: 100, height: 100) { x, y in
            (x >= 10 && x < 18 && y >= 10 && y < 18) || (x >= 35 && x < 90 && y >= 20 && y < 90) ? 255 : 0
        }
        let result = SilhouetteTextLayout.layout(text: "largest component", alphaImage: image, canvasSize: CGSize(width: 200, height: 200), fontSize: 14)
        #expect(result.path.boundingBox.minX > 60)
        #expect(!result.path.contains(CGPoint(x: 28, y: 28)))
    }

    @Test func narrowAndTransparentMasksFallback() {
        let narrow = mask(width: 200, height: 80) { x, _ in x >= 95 && x < 101 ? 255 : 0 }
        let empty = mask(width: 40, height: 90) { _, _ in 0 }
        #expect(SilhouetteTextLayout.layout(text: "note", alphaImage: narrow, canvasSize: CGSize(width: 300, height: 120), fontSize: 15).usesFallbackCard)
        #expect(SilhouetteTextLayout.layout(text: "note", alphaImage: empty, canvasSize: CGSize(width: 120, height: 270), fontSize: 15).usesFallbackCard)
    }

    @Test func alphaThresholdRejectsTransparentAndAcceptsSemitransparentPixels() {
        let image = mask(width: 80, height: 80) { x, _ in x < 40 ? 40 : 180 }
        let result = SilhouetteTextLayout.layout(text: "threshold", alphaImage: image, canvasSize: CGSize(width: 160, height: 160), fontSize: 12)
        #expect(result.path.boundingBox.minX >= 80)
    }

    @Test func reportsOverflowAndIsDeterministicForNonSquareMask() {
        let image = mask(width: 160, height: 60) { x, y in x > 8 && x < 152 && y > 6 && y < 54 ? 255 : 0 }
        let text = String(repeating: "overflowing text ", count: 100)
        let first = SilhouetteTextLayout.layout(text: text, alphaImage: image, canvasSize: CGSize(width: 320, height: 120), fontSize: 15)
        let second = SilhouetteTextLayout.layout(text: text, alphaImage: image, canvasSize: CGSize(width: 320, height: 120), fontSize: 15)
        #expect(first.overflowed)
        #expect(first.lines == second.lines)
        #expect(first.path.boundingBox == second.path.boundingBox)
    }

    @Test func dynamicTypeRaisesMinimumUsableWidth() {
        let image = mask(width: 100, height: 100) { x, y in x >= 25 && x < 75 && y >= 10 && y < 90 ? 255 : 0 }
        let normal = SilhouetteTextLayout.layout(text: "note", alphaImage: image, canvasSize: CGSize(width: 200, height: 200), fontSize: 14, sizeCategory: .large)
        let accessibility = SilhouetteTextLayout.layout(text: "note", alphaImage: image, canvasSize: CGSize(width: 200, height: 200), fontSize: 14, sizeCategory: .accessibilityExtraExtraExtraLarge)
        #expect(!normal.usesFallbackCard)
        #expect(accessibility.usesFallbackCard)
    }

    @Test(arguments: ["u", "donut", "concave"])
    func pathsAndTextNeverBridgeTransparentGaps(shape: String) {
        let image = mask(width: 120, height: 120) { x, y in
            switch shape {
            case "u": return ((x >= 10 && x < 35) || (x >= 85 && x < 110) || (y >= 85 && x >= 10 && x < 110)) && y >= 10 && y < 110 ? 255 : 0
            case "donut":
                let dx = x - 60, dy = y - 60, radius = dx * dx + dy * dy
                return radius <= 52 * 52 && radius >= 25 * 25 ? 255 : 0
            default: return (x >= 8 && x < 112 && y >= 8 && y < 112 && !(x >= 42 && y >= 45 && y < 78)) ? 255 : 0
            }
        }
        let canvas = CGSize(width: 240, height: 240)
        let result = SilhouetteTextLayout.layout(text: String(repeating: "safe words ", count: 60), alphaImage: image, canvasSize: canvas, fontSize: 12)

        if shape == "donut" { #expect(!result.path.contains(CGPoint(x: 120, y: 120))) }
        for line in result.lines {
            for y in stride(from: line.rect.minY, through: line.rect.maxY, by: 2) {
                for x in stride(from: line.rect.minX, through: line.rect.maxX, by: 2) {
                    let sourceX = min(119, max(0, Int(x / canvas.width * 120)))
                    let sourceY = min(119, max(0, Int(y / canvas.height * 120)))
                    #expect(alphaAt(image, x: sourceX, y: sourceY) >= 96)
                }
            }
        }
    }

    private func mask(width: Int, height: Int, alpha: (Int, Int) -> UInt8) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height { for x in 0..<width { bytes[(y * width + x) * 4 + 3] = alpha(x, y) } }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    private func alphaAt(_ image: CGImage, x: Int, y: Int) -> UInt8 {
        let data = image.dataProvider!.data!
        return CFDataGetBytePtr(data)![y * image.bytesPerRow + x * 4 + 3]
    }
}
