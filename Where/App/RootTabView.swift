import Observation
import SwiftUI

enum RootTabSelection: Hashable {
    case scenes
    case items
}

enum AddSceneAccessoryPresentation: Equatable {
    case iconOnly
    case labeled

    static func forPlacement(
        _ placement: TabViewBottomAccessoryPlacement?
    ) -> AddSceneAccessoryPresentation {
        placement == .inline ? .iconOnly : .labeled
    }
}

@MainActor
@Observable
final class RootTabState {
    var selection: RootTabSelection
    var isPresentingCapture = false

    init(selection: RootTabSelection = .scenes) {
        self.selection = selection
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
                NavigationStack {
                    ContentUnavailableView(
                        "还没有物品",
                        systemImage: "shippingbox",
                        description: Text("场景中的物品会显示在这里。")
                    )
                    .navigationTitle("所有物品")
                }
            }
        }
        .tabViewBottomAccessory {
            AddSceneAccessoryButton(action: state.presentCapture)
        }
        .fullScreenCover(isPresented: $state.isPresentingCapture) {
            SceneDraftView(
                repository: dependencies.itemRepository,
                imageStore: dependencies.imageStore
            )
        }
    }
}

private struct AddSceneAccessoryButton: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch AddSceneAccessoryPresentation.forPlacement(placement) {
            case .iconOnly:
                Label("添加场景", systemImage: "plus")
                    .labelStyle(.iconOnly)
            case .labeled:
                Label("添加场景", systemImage: "plus")
            }
        }
        .buttonStyle(.glassProminent)
        .accessibilityLabel("添加场景")
        .accessibilityIdentifier("add-scene-button")
    }
}
