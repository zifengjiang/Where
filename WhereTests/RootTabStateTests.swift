import Foundation
import SwiftUI
import Testing
@testable import Where

@MainActor
struct RootTabStateTests {
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
    func startupBeginsLoadingThenRetainsExactDependencies() async throws {
        let dependencies = try AppDependencies.testing()
        let startup = AppStartupModel { () async throws -> AppDependencies in
            dependencies
        }

        guard case .loading = startup.state else {
            Issue.record("Expected startup to begin loading")
            return
        }

        await startup.load()

        guard case .ready(let ready) = startup.state else {
            Issue.record("Expected dependency startup to succeed")
            return
        }
        #expect(ready.database === dependencies.database)
        #expect(ready.imageStore === dependencies.imageStore)
        let readySceneRepository = try #require(ready.sceneRepository as? SceneRepository)
        let expectedSceneRepository = try #require(dependencies.sceneRepository as? SceneRepository)
        let readyItemRepository = try #require(ready.itemRepository as? ItemRepository)
        let expectedItemRepository = try #require(dependencies.itemRepository as? ItemRepository)
        #expect(readySceneRepository === expectedSceneRepository)
        #expect(readyItemRepository === expectedItemRepository)
        #expect(readyItemRepository.sceneRepository === readySceneRepository)

        let root = RootTabView(dependencies: ready)
        #expect(root.dependencies.database === dependencies.database)
        #expect(root.dependencies.imageStore === dependencies.imageStore)
    }

    @Test
    func failedStartupCanRetrySuccessfully() async throws {
        let dependencies = try AppDependencies.testing()
        let attempts = StartupAttempts(dependencies: dependencies)
        let startup = AppStartupModel { () async throws -> AppDependencies in
            try await attempts.load()
        }

        await startup.load()
        guard case .failed(let message) = startup.state else {
            Issue.record("Expected first dependency startup to fail")
            return
        }
        #expect(message == "Storage is unavailable")

        await startup.load()
        guard case .ready(let ready) = startup.state else {
            Issue.record("Expected retry to succeed")
            return
        }
        #expect(ready.database === dependencies.database)
    }

    @Test
    func staleLoadCannotOverwriteNewerRetry() async throws {
        let staleDependencies = try AppDependencies.testing()
        let currentDependencies = try AppDependencies.testing()
        let loads = ControlledStartupLoads(
            stale: staleDependencies,
            current: currentDependencies
        )
        let startup = AppStartupModel { () async throws -> AppDependencies in
            await loads.load()
        }

        let staleLoad = Task { await startup.load() }
        await loads.waitUntilFirstLoadStarts()
        await startup.load()
        await loads.finishFirstLoad()
        await staleLoad.value

        guard case .ready(let ready) = startup.state else {
            Issue.record("Expected the retry result to remain ready")
            return
        }
        #expect(ready.database === currentDependencies.database)
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

private actor StartupAttempts {
    private struct StartupFailure: LocalizedError {
        var errorDescription: String? { "Storage is unavailable" }
    }

    private var attempt = 0
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    func load() throws -> AppDependencies {
        attempt += 1
        if attempt == 1 {
            throw StartupFailure()
        }
        return dependencies
    }
}

private actor ControlledStartupLoads {
    private let stale: AppDependencies
    private let current: AppDependencies
    private var callCount = 0
    private var firstLoadContinuation: CheckedContinuation<AppDependencies, Never>?
    private var firstLoadWaiter: CheckedContinuation<Void, Never>?

    init(stale: AppDependencies, current: AppDependencies) {
        self.stale = stale
        self.current = current
    }

    func load() async -> AppDependencies {
        callCount += 1
        guard callCount == 1 else { return current }
        return await withCheckedContinuation { continuation in
            firstLoadContinuation = continuation
            firstLoadWaiter?.resume()
            firstLoadWaiter = nil
        }
    }

    func waitUntilFirstLoadStarts() async {
        guard firstLoadContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            firstLoadWaiter = continuation
        }
    }

    func finishFirstLoad() {
        firstLoadContinuation?.resume(returning: stale)
        firstLoadContinuation = nil
    }
}
