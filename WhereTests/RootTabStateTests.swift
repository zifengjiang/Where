import Foundation
import SwiftUI
import Testing
@testable import Where

@MainActor
struct RootTabStateTests {
    private struct StartupFailure: LocalizedError {
        var errorDescription: String? { "Storage is unavailable" }
    }

    @Test
    func defaultsToScenes() {
        let state = RootTabState()

        #expect(state.selection == .scenes)
        #expect(!state.isPresentingCapture)
    }

    @Test
    func selectsEachContentTab() {
        let state = RootTabState()

        state.select(.items)
        #expect(state.selection == .items)

        state.select(.scenes)
        #expect(state.selection == .scenes)
    }

    @Test
    func presentingCaptureDoesNotChangeSelection() {
        let state = RootTabState(selection: .items)

        state.presentCapture()

        #expect(state.selection == .items)
        #expect(state.isPresentingCapture)
    }

    @Test
    func dismissingCaptureResetsPresentation() {
        let state = RootTabState()
        state.presentCapture()

        state.dismissCapture()

        #expect(!state.isPresentingCapture)
    }

    @Test
    func presentingCaptureRepeatedlyIsIdempotent() {
        let state = RootTabState(selection: .items)

        state.presentCapture()
        state.presentCapture()

        #expect(state.selection == .items)
        #expect(state.isPresentingCapture)
    }

    @Test
    func dependencyFailureProducesRecoverableStartupState() {
        let startup = AppStartupState.load {
            throw StartupFailure()
        }

        guard case .failed(let message) = startup else {
            Issue.record("Expected dependency startup to fail")
            return
        }
        #expect(message == "Storage is unavailable")
    }

    @Test(arguments: [
        (TabViewBottomAccessoryPlacement.inline, AddSceneAccessoryPresentation.iconOnly),
        (.expanded, .labeled),
    ])
    func accessoryPresentationAdaptsToPlacement(
        placement: TabViewBottomAccessoryPlacement,
        expected: AddSceneAccessoryPresentation
    ) {
        #expect(AddSceneAccessoryPresentation.forPlacement(placement) == expected)
    }
}
