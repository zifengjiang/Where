import SwiftUI

@main
struct WhereApp: App {
    @State private var startup: AppStartupState

    init() {
        _startup = State(initialValue: AppStartupState.load())
    }

    var body: some Scene {
        WindowGroup {
            switch startup {
            case .ready:
                RootTabView()
            case .failed(let message):
                ContentUnavailableView {
                    Label("无法启动", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") {
                        startup = AppStartupState.load()
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
    }
}

enum AppStartupState {
    case ready(AppDependencies)
    case failed(String)

    static func load(
        makeDependencies: () throws -> AppDependencies = { try AppDependencies.production() }
    ) -> AppStartupState {
        do {
            return .ready(try makeDependencies())
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
