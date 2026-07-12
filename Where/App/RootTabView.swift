import Observation
import SwiftUI

enum WhereTheme {
    static let canvas = Color(red: 0.969, green: 0.945, blue: 0.906)
    static let surface = Color(red: 1.0, green: 0.976, blue: 0.937)
    static let ink = Color(red: 0.09, green: 0.247, blue: 0.208)
    static let orange = Color(red: 0.91, green: 0.604, blue: 0.29)
    static let pin = Color(red: 0.851, green: 0.361, blue: 0.29)
    static let paper = Color(red: 0.949, green: 0.867, blue: 0.722)
    static let pagePadding: CGFloat = 16
    static let cardRadius: CGFloat = 20
}

enum RootTabSelection: Hashable {
    case scenes
    case items
    case add
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
    var selection: RootTabSelection {
        didSet {
            if selection == .add {
                selection = previousContentSelection
                isPresentingCapture = true
            } else {
                previousContentSelection = selection
            }
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

            Tab("添加", systemImage: "plus", value: .add, role: .search) {
                Color.clear.accessibilityHidden(true)
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
