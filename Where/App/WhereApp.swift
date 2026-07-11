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
    private var loadGeneration = 0

    init(
        makeDependencies: @escaping DependencyLoader = {
            try await AppDependencies.production()
        }
    ) {
        self.makeDependencies = makeDependencies
    }

    func loadIfNeeded() async {
        guard case .loading = state, loadGeneration == 0 else { return }
        await load()
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        state = .loading

        do {
            let dependencies = try await makeDependencies()
            guard generation == loadGeneration else { return }
            guard !Task.isCancelled else {
                resetCancelledLoad(generation: generation)
                return
            }
            state = .ready(dependencies)
        } catch is CancellationError {
            resetCancelledLoad(generation: generation)
        } catch {
            guard generation == loadGeneration else { return }
            guard !Task.isCancelled else {
                resetCancelledLoad(generation: generation)
                return
            }
            state = .failed(error.localizedDescription)
        }
    }

    private func resetCancelledLoad(generation: Int) {
        guard generation == loadGeneration else { return }
        loadGeneration = 0
        state = .loading
    }
}
