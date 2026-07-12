import CoreGraphics
import Foundation
import Testing
@testable import Where

struct SubjectSelectionTests {
    @Test func defaultsToCandidateWithGreatestNormalizedArea() {
        let state = SubjectSelectionState(candidates: [
            candidate("small", x: 0, y: 0, width: 0.2, height: 0.2),
            candidate("large", x: 0.1, y: 0.1, width: 0.7, height: 0.6),
        ])

        #expect(state.selectedID == "large")
    }

    @Test func equalAreasUseStableIDAsDeterministicTieBreak() {
        let state = SubjectSelectionState(candidates: [
            candidate("zebra", x: 0, y: 0, width: 0.5, height: 0.5),
            candidate("apple", x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        ])

        #expect(state.selectedID == "apple")
    }

    @Test func emptyCandidatesHaveNoSelection() {
        #expect(SubjectSelectionState(candidates: []).selectedID == nil)
    }

    @Test func explicitSelectionSurvivesCandidateReordering() {
        var state = SubjectSelectionState(candidates: [
            candidate("a", x: 0, y: 0, width: 0.8, height: 0.8),
            candidate("b", x: 0.2, y: 0.2, width: 0.2, height: 0.2),
        ])
        state.select(id: "b")

        state.updateCandidates([
            candidate("b", x: 0.2, y: 0.2, width: 0.2, height: 0.2),
            candidate("a", x: 0, y: 0, width: 0.8, height: 0.8),
        ])

        #expect(state.selectedID == "b")
    }

    @Test func invalidBoundsAreIgnored() {
        let state = SubjectSelectionState(candidates: [
            candidate("zero", x: 0, y: 0, width: 0, height: 1),
            candidate("negative", x: 0, y: 0, width: -1, height: 1),
            candidate("nan", x: .nan, y: 0, width: 1, height: 1),
            candidate("infinite", x: 0, y: 0, width: .infinity, height: 1),
            candidate("valid", x: 0.1, y: 0.1, width: 0.2, height: 0.2),
        ])

        #expect(state.candidates.map(\.id) == ["valid"])
        #expect(state.selectedID == "valid")
    }

    @Test func tapSelectsMostSpecificContainingCandidateThenStableID() {
        var state = SubjectSelectionState(candidates: [
            candidate("background", x: 0, y: 0, width: 1, height: 1),
            candidate("z-top", x: 0.2, y: 0.2, width: 0.2, height: 0.2),
            candidate("a-top", x: 0.2, y: 0.2, width: 0.2, height: 0.2),
        ])

        state.select(at: CGPoint(x: 0.25, y: 0.25))

        #expect(state.selectedID == "a-top")
    }

    @Test func tapOutsideCandidatesDoesNotDiscardSelection() {
        var state = SubjectSelectionState(candidates: [candidate("subject", x: 0.1, y: 0.1, width: 0.2, height: 0.2)])

        state.select(at: CGPoint(x: 0.9, y: 0.9))

        #expect(state.selectedID == "subject")
    }

    @Test func accessibilityCandidatesPreserveDetectionOrderAndDescribeSelection() {
        var state = SubjectSelectionState(candidates: [
            candidate("second", x: 0.5, y: 0, width: 0.2, height: 0.2),
            candidate("first", x: 0, y: 0, width: 0.8, height: 0.8),
        ])
        state.select(id: "second")

        let descriptors = state.accessibilityCandidates

        #expect(descriptors.map(\.candidateID) == ["second", "first"])
        #expect(descriptors.map(\.label) == ["主体 1", "主体 2"])
        #expect(descriptors.map(\.isSelected) == [true, false])
        #expect(descriptors.map(\.value) == ["已选择", "未选择"])
    }

    @Test func selectionAnnouncementIsChinese() {
        #expect(SubjectAccessibility.selectionAnnouncement(label: "主体 2") == "主体 2，已选择")
    }

    @Test @MainActor func segmentationErrorsPassThroughErrorMapping() {
        #expect(SubjectSegmentationService.map(SubjectSegmentationError.noSubjects) == .noSubjects)
    }

    @Test @MainActor func unknownFrameworkErrorsMapToRecoverableAnalysisFailure() {
        let frameworkError = NSError(domain: "VisionKit", code: 42)

        #expect(SubjectSegmentationService.map(frameworkError) == .analysisFailed)
    }

    private func candidate(
        _ id: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> SubjectCandidate {
        let normalized = CGRect(x: x, y: y, width: width, height: height)
        return SubjectCandidate(id: id, normalizedBounds: normalized, displayBounds: normalized)
    }
}

struct SubjectPickerCompletionCoordinatorTests {
    @Test @MainActor func originalSuppressesLateCutoutCompletion() async {
        let coordinator = SubjectPickerCompletionCoordinator()
        let token = coordinator.beginConfirmation()
        var originalCount = 0
        var cutoutCount = 0

        if coordinator.claimOriginal() { originalCount += 1 }
        await Task.yield()
        if let token, coordinator.claimCutout(token: token) { cutoutCount += 1 }

        #expect(originalCount == 1)
        #expect(cutoutCount == 0)
    }

    @Test @MainActor func repeatedTerminalActionsAreClaimedOnlyOnce() {
        let coordinator = SubjectPickerCompletionCoordinator()
        var callbackCount = 0

        if coordinator.claimOriginal() { callbackCount += 1 }
        if coordinator.claimOriginal() { callbackCount += 1 }
        if let token = coordinator.beginConfirmation(), coordinator.claimCutout(token: token) {
            callbackCount += 1
        }

        #expect(callbackCount == 1)
        #expect(coordinator.isCompleted)
    }
}
