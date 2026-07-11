import Observation
import SwiftUI

@main
struct WhereApp: App {
    @State private var startup = AppStartupModel()

    var body: some Scene {
        WindowGroup {
            Group {
                switch startup.state {
                case .loading:
                    ProgressView("正在启动…")
                case .ready(let dependencies):
                    RootTabView(dependencies: dependencies)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("无法启动", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重试") {
                            Task {
                                await startup.load()
                            }
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            }
            .task {
                await startup.loadIfNeeded()
            }
        }
    }
}

enum AppStartupState {
    case loading
    case ready(AppDependencies)
    case failed(String)
}

@MainActor
@Observable
final class AppStartupModel {
    typealias DependencyLoader = @Sendable () async throws -> AppDependencies

    private(set) var state: AppStartupState = .loading
    private let makeDependencies: DependencyLoader
    private var nextGeneration = 0
    private var activeGeneration: Int?

    init(
        makeDependencies: @escaping DependencyLoader = {
            try await AppDependencies.production()
        }
    ) {
        self.makeDependencies = makeDependencies
    }

    func loadIfNeeded() async {
        guard case .loading = state, activeGeneration == nil else { return }
        await load()
    }

    func load() async {
        nextGeneration += 1
        let generation = nextGeneration
        activeGeneration = generation
        state = .loading

        do {
            let dependencies = try await makeDependencies()
            guard generation == activeGeneration else { return }
            guard !Task.isCancelled else {
                resetCancelledLoad(generation: generation)
                return
            }
            activeGeneration = nil
            state = .ready(dependencies)
        } catch is CancellationError {
            resetCancelledLoad(generation: generation)
        } catch {
            guard generation == activeGeneration else { return }
            guard !Task.isCancelled else {
                resetCancelledLoad(generation: generation)
                return
            }
            activeGeneration = nil
            state = .failed(error.localizedDescription)
        }
    }

    private func resetCancelledLoad(generation: Int) {
        guard generation == activeGeneration else { return }
        activeGeneration = nil
        state = .loading
    }
}
