import CoreGraphics
import Testing
@testable import Where

struct AspectFitGeometryTests {
    @Test func portraitImageInLandscapeContainerHasHorizontalLetterboxing() {
        let geometry = AspectFitGeometry(imageSize: CGSize(width: 300, height: 600), containerSize: CGSize(width: 800, height: 400))

        #expect(geometry.imageRect == CGRect(x: 300, y: 0, width: 200, height: 400))
    }

    @Test func landscapeImageInPortraitContainerHasVerticalLetterboxing() {
        let geometry = AspectFitGeometry(imageSize: CGSize(width: 800, height: 400), containerSize: CGSize(width: 300, height: 600))

        #expect(geometry.imageRect == CGRect(x: 0, y: 225, width: 300, height: 150))
    }

    @Test func sameAspectImageFillsContainer() {
        let geometry = AspectFitGeometry(imageSize: CGSize(width: 400, height: 200), containerSize: CGSize(width: 1000, height: 500))

        #expect(geometry.imageRect == CGRect(x: 0, y: 0, width: 1000, height: 500))
    }

    @Test(arguments: [
        CGPoint(x: 299.999, y: 200),
        CGPoint(x: 500.001, y: 200),
        CGPoint(x: 400, y: -0.001),
        CGPoint(x: 400, y: 400.001),
    ])
    func rejectsTapsOutsideEveryImageRectEdge(point: CGPoint) {
        let geometry = AspectFitGeometry(imageSize: CGSize(width: 300, height: 600), containerSize: CGSize(width: 800, height: 400))

        #expect(geometry.normalizedPoint(for: point) == nil)
    }

    @Test(arguments: [
        (CGPoint(x: 300, y: 0), CGPoint(x: 0, y: 0)),
        (CGPoint(x: 500, y: 0), CGPoint(x: 1, y: 0)),
        (CGPoint(x: 300, y: 400), CGPoint(x: 0, y: 1)),
        (CGPoint(x: 500, y: 400), CGPoint(x: 1, y: 1)),
    ])
    func acceptsImageRectBoundaries(point: CGPoint, expected: CGPoint) {
        let geometry = AspectFitGeometry(imageSize: CGSize(width: 300, height: 600), containerSize: CGSize(width: 800, height: 400))

        #expect(geometry.normalizedPoint(for: point) == expected)
    }

    @Test func convertsViewPointToNormalizedCoordinates() {
        let geometry = AspectFitGeometry(imageSize: CGSize(width: 800, height: 400), containerSize: CGSize(width: 300, height: 600))

        #expect(geometry.normalizedPoint(for: CGPoint(x: 75, y: 300)) == CGPoint(x: 0.25, y: 0.5))
    }

    @Test func normalizedAndViewCoordinatesRoundTrip() {
        let geometry = AspectFitGeometry(imageSize: CGSize(width: 4032, height: 3024), containerSize: CGSize(width: 393, height: 852))
        let normalized = CGPoint(x: 0.137, y: 0.826)

        let viewPoint = geometry.viewPoint(for: normalized)
        let roundTrip = geometry.normalizedPoint(for: viewPoint)

        #expect(roundTrip != nil)
        #expect(abs(roundTrip!.x - normalized.x) < 0.000_000_1)
        #expect(abs(roundTrip!.y - normalized.y) < 0.000_000_1)
    }

    @Test(arguments: [
        (CGSize.zero, CGSize(width: 100, height: 100)),
        (CGSize(width: 100, height: 100), CGSize.zero),
        (CGSize(width: -1, height: 100), CGSize(width: 100, height: 100)),
        (CGSize(width: 100, height: 100), CGSize(width: 100, height: -.infinity)),
        (CGSize(width: CGFloat.nan, height: 100), CGSize(width: 100, height: 100)),
    ])
    func invalidDimensionsProduceZeroRectAndNoTapConversion(imageSize: CGSize, containerSize: CGSize) {
        let geometry = AspectFitGeometry(imageSize: imageSize, containerSize: containerSize)

        #expect(geometry.imageRect == .zero)
        #expect(geometry.normalizedPoint(for: CGPoint(x: 0, y: 0)) == nil)
        #expect(geometry.viewPoint(for: CGPoint(x: 0.5, y: 0.5)) == .zero)
    }

    @Test(arguments: [
        (CGPoint(x: -2, y: 3), CGPoint(x: 0, y: 100)),
        (CGPoint(x: 0.25, y: 0.75), CGPoint(x: 25, y: 75)),
    ])
    func clampsNormalizedInputToUnitSquare(normalized: CGPoint, expected: CGPoint) {
        let geometry = AspectFitGeometry(imageSize: CGSize(width: 100, height: 100), containerSize: CGSize(width: 100, height: 100))

        #expect(geometry.viewPoint(for: normalized) == expected)
    }

    @Test(arguments: [
        CGPoint(x: CGFloat.nan, y: 0.5),
        CGPoint(x: 0.5, y: .infinity),
    ])
    func nonFiniteNormalizedInputProducesZeroPoint(normalized: CGPoint) {
        let geometry = AspectFitGeometry(imageSize: CGSize(width: 100, height: 100), containerSize: CGSize(width: 100, height: 100))

        #expect(geometry.viewPoint(for: normalized) == .zero)
    }

    @Test(arguments: [
        CGPoint(x: CGFloat.nan, y: 50),
        CGPoint(x: 50, y: -.infinity),
    ])
    func rejectsNonFiniteViewPoints(point: CGPoint) {
        let geometry = AspectFitGeometry(imageSize: CGSize(width: 100, height: 100), containerSize: CGSize(width: 100, height: 100))

        #expect(geometry.normalizedPoint(for: point) == nil)
    }
}
