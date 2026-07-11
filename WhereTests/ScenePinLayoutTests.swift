import CoreGraphics
import Testing
@testable import Where

struct ScenePinLayoutTests {
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
