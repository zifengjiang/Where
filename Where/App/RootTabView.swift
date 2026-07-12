import Observation
import SwiftUI

enum RootTabSelection: Hashable {
    case scenes
    case items
    case add
}

@MainActor
@Observable
final class RootTabState {
    var selection: RootTabSelection {
        didSet {
            if selection == .add {
                selection = previousContentSelection
                isPresentingCapture = true
            } else { previousContentSelection = selection }
        }
    }
    var isPresentingCapture = false
    private var previousContentSelection: RootTabSelection

    init(selection: RootTabSelection = .scenes) {
        self.selection = selection
        self.previousContentSelection = selection
    }

    func select(_ selection: RootTabSelection) { self.selection = selection }
    func presentCapture() { isPresentingCapture = true }
    func dismissCapture() { isPresentingCapture = false }
}

struct RootTabView: View {
    let dependencies: AppDependencies

    @State private var state = RootTabState()

    var body: some View {
        @Bindable var state = state

        TabView(selection: $state.selection) {
            Tab("场景", systemImage: "photo.on.rectangle", value: .scenes) {
                ScenesView(repository: dependencies.sceneRepository, imageStore: dependencies.imageStore)
            }

            Tab("所有物品", systemImage: "shippingbox", value: .items) {
                ItemsView(repository: dependencies.itemRepository, imageStore: dependencies.imageStore)
            }
            Tab(value: .add, role: .search) {
                Color.clear.accessibilityHidden(true)
            } label: {
                Label("添加场景", systemImage: "plus")
                    .accessibilityLabel("添加场景")
                    .accessibilityHint("打开系统相机记录新场景")
            }
        }
        .tint(WhereTheme.pin)
        .fullScreenCover(isPresented: $state.isPresentingCapture) {
            SceneDraftView(
                repository: dependencies.itemRepository,
                imageStore: dependencies.imageStore
            )
        }
    }
}
