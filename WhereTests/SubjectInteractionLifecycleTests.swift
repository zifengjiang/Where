import Testing
import UIKit
import VisionKit
@testable import Where

struct SubjectInteractionLifecycleTests {
    @Test @MainActor func replacingInteractionDetachesOldInteractionAndCancelsTap() {
        let imageView = UIImageView()
        let oldInteraction = ImageAnalysisInteraction()
        let newInteraction = ImageAnalysisInteraction()
        let lifecycle = SubjectInteractionLifecycle()

        lifecycle.replaceInteraction(on: imageView, with: oldInteraction)
        lifecycle.trackTap(Task {})
        lifecycle.replaceInteraction(on: imageView, with: newInteraction)

        #expect(oldInteraction.view == nil)
        #expect(newInteraction.view === imageView)
        #expect(!lifecycle.hasTrackedTap)
    }

    @Test @MainActor func dismantleDetachesInteractionAndCancelsTap() {
        let imageView = UIImageView()
        let interaction = ImageAnalysisInteraction()
        let lifecycle = SubjectInteractionLifecycle()

        lifecycle.replaceInteraction(on: imageView, with: interaction)
        lifecycle.trackTap(Task {})
        lifecycle.dismantle(from: imageView)

        #expect(interaction.view == nil)
        #expect(!lifecycle.hasTrackedTap)
    }
}
