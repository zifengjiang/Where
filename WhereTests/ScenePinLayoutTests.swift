import CoreGraphics
import Testing
@testable import Where

@Test func sceneGridAdaptsToWidthAndAccessibilityText() {
    #expect(SceneGridPolicy.columnCount(availableWidth: 393, isAccessibilitySize: true) == 1)
    #expect(SceneGridPolicy.columnCount(availableWidth: 393, isAccessibilitySize: false) == 2)
    #expect(SceneGridPolicy.columnCount(availableWidth: 320, isAccessibilitySize: false) == 1)
    #expect(SceneGridPolicy.imageHeight(forCardWidth: 180) == 135)
}

@Test func semanticPinPresentationKeepsVisualAndHitSizesSeparate() {
    #expect(ScenePinPresentation.selectedDiameter == 28)
    #expect(ScenePinPresentation.normalDiameter == 20)
    #expect(ScenePinPresentation.hitTarget == 44)
}

@Test func emptySceneCompletionRequiresConfirmation() {
    #expect(MarkerCompletionPolicy.requiresEmptyConfirmation(itemCount: 0))
    #expect(!MarkerCompletionPolicy.requiresEmptyConfirmation(itemCount: 1))
}

struct ScenePinLayoutTests {
    @Test func selectedLabelStaysInsideViewportAtEveryCorner() {
        let viewport = CGSize(width: 320, height: 480)
        let label = CGSize(width: 220, height: 58)
        for anchor in [CGPoint(x: 0, y: 0), CGPoint(x: 320, y: 0), CGPoint(x: 0, y: 480), CGPoint(x: 320, y: 480)] {
            let center = ScenePinLabelLayout.center(anchor: anchor, labelSize: label, viewport: viewport)
            let frame = CGRect(x: center.x - label.width / 2, y: center.y - label.height / 2, width: label.width, height: label.height)
            #expect(frame.minX >= 8 && frame.maxX <= 312)
            #expect(frame.minY >= 8 && frame.maxY <= 472)
        }
    }
    @Test(arguments: [
        CGSize.zero,
        CGSize(width: 80, height: 20),
        CGSize(width: 240, height: 120),
    ])
    func anchorFrameStaysCenteredAndFixedWhenLabelSizeChanges(labelSize: CGSize) {
        let center = CGPoint(x: 123.5, y: 456.25)
        let layout = ScenePinLayout(anchorCenter: center)

        #expect(layout.anchorFrame == CGRect(x: 101.5, y: 434.25, width: 44, height: 44))
        #expect(layout.labelFrame(for: labelSize).midX == center.x)
        #expect(layout.anchorFrame.midX == center.x)
        #expect(layout.anchorFrame.midY == center.y)
    }

    @Test func labelIsPlacedBelowAnchorWithoutChangingItsFrame() {
        let layout = ScenePinLayout(anchorCenter: CGPoint(x: 100, y: 100))

        #expect(layout.labelFrame(for: CGSize(width: 120, height: 36)) == CGRect(x: 40, y: 126, width: 120, height: 36))
        #expect(layout.anchorFrame == CGRect(x: 78, y: 78, width: 44, height: 44))
    }
}
