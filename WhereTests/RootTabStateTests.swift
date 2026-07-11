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

    @Test
    func cancelledLoadThatReturnsCanRestartWithLoadIfNeeded() async throws {
        let cancelledDependencies = try AppDependencies.testing()
        let restartedDependencies = try AppDependencies.testing()
        let loads = ControlledStartupLoads(
            stale: cancelledDependencies,
            current: restartedDependencies
        )
        let startup = AppStartupModel { () async throws -> AppDependencies in
            await loads.load()
        }

        let cancelledLoad = Task { await startup.load() }
        await loads.waitUntilFirstLoadStarts()
        cancelledLoad.cancel()
        await loads.finishFirstLoad()
        await cancelledLoad.value

        guard case .loading = startup.state else {
            Issue.record("Expected cancellation to return startup to loading")
            return
        }

        await startup.loadIfNeeded()

        guard case .ready(let ready) = startup.state else {
            Issue.record("Expected startup to restart after cancellation")
            return
        }
        #expect(ready.database === restartedDependencies.database)
    }

    @Test
    func generationsStayUniqueAcrossCancelledRetryAndRestart() async throws {
        let firstDependencies = try AppDependencies.testing()
        let cancelledDependencies = try AppDependencies.testing()
        let currentDependencies = try AppDependencies.testing()
        let loads = ThreeGenerationStartupLoads(
            first: firstDependencies,
            second: cancelledDependencies,
            third: currentDependencies
        )
        let startup = AppStartupModel { () async throws -> AppDependencies in
            await loads.load()
        }

        let firstLoad = Task { await startup.load() }
        await loads.waitUntilLoadStarts(1)

        let cancelledLoad = Task { await startup.load() }
        await loads.waitUntilLoadStarts(2)
        cancelledLoad.cancel()
        await loads.finishLoad(2)
        await cancelledLoad.value

        await startup.loadIfNeeded()
        await loads.finishLoad(1)
        await firstLoad.value

        guard case .ready(let ready) = startup.state else {
            Issue.record("Expected the third generation to remain ready")
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

private actor ThreeGenerationStartupLoads {
    private let dependencies: [AppDependencies]
    private var callCount = 0
    private var continuations: [Int: CheckedContinuation<AppDependencies, Never>] = [:]
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]

    init(first: AppDependencies, second: AppDependencies, third: AppDependencies) {
        dependencies = [first, second, third]
    }

    func load() async -> AppDependencies {
        callCount += 1
        let call = callCount
        guard call < 3 else { return dependencies[2] }
        return await withCheckedContinuation { continuation in
            continuations[call] = continuation
            waiters.removeValue(forKey: call)?.resume()
        }
    }

    func waitUntilLoadStarts(_ load: Int) async {
        guard continuations[load] == nil else { return }
        await withCheckedContinuation { continuation in
            waiters[load] = continuation
        }
    }

    func finishLoad(_ load: Int) {
        continuations.removeValue(forKey: load)?.resume(returning: dependencies[load - 1])
    }
}
