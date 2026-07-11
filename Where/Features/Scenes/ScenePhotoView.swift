import SwiftUI
import UIKit

struct ScenePin: Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let locationNote: String?
    let normalizedPoint: CGPoint

    init(id: UUID, name: String, locationNote: String? = nil, normalizedPoint: CGPoint) {
        self.id = id
        self.name = name
        self.locationNote = locationNote
        self.normalizedPoint = normalizedPoint
    }
}

struct ScenePhotoView: View {
    let image: UIImage
    let pins: [ScenePin]
    let selectedItemID: UUID?
    var onImageTap: ((CGPoint) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let geometry = AspectFitGeometry(imageSize: image.size, containerSize: proxy.size)

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .accessibilityHidden(true)

                ForEach(pins) { pin in
                    marker(for: pin, selected: pin.id == selectedItemID)
                        .position(geometry.viewPoint(for: pin.normalizedPoint))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { point in
                guard let normalizedPoint = geometry.normalizedPoint(for: point) else { return }
                onImageTap?(normalizedPoint)
            }
        }
        .clipped()
    }

    private func marker(for pin: ScenePin, selected: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(.tint)
                    .frame(width: selected ? 28 : 20, height: selected ? 28 : 20)
                Circle()
                    .stroke(selected ? Color.white : Color.black.opacity(0.65), lineWidth: selected ? 3 : 2)
                    .frame(width: selected ? 28 : 20, height: selected ? 28 : 20)
            }

            if selected {
                Text(pin.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .fixedSize()
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pin.name)
        .accessibilityHint(accessibilityHint(for: pin))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func accessibilityHint(for pin: ScenePin) -> Text {
        if let note = pin.locationNote, !note.isEmpty {
            Text(note)
        } else {
            Text("Located in this scene")
        }
    }
}

#Preview("Portrait phone") {
    ScenePhotoView(
        image: ScenePhotoPreviewFixture.image,
        pins: ScenePhotoPreviewFixture.pins,
        selectedItemID: ScenePhotoPreviewFixture.pins.first?.id
    )
    .frame(width: 393, height: 852)
    .background(.black)
}

#Preview("Landscape device") {
    ScenePhotoView(
        image: ScenePhotoPreviewFixture.image,
        pins: ScenePhotoPreviewFixture.pins,
        selectedItemID: ScenePhotoPreviewFixture.pins.last?.id
    )
    .frame(width: 852, height: 393)
    .background(.black)
}

@MainActor
private enum ScenePhotoPreviewFixture {
    static let image = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 500)).image { context in
        UIColor.systemIndigo.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 500))
        UIColor.systemTeal.setFill()
        context.fill(CGRect(x: 80, y: 80, width: 640, height: 340))
    }

    static let pins = [
        ScenePin(id: UUID(), name: "Keys", locationNote: "On the left shelf", normalizedPoint: CGPoint(x: 0.25, y: 0.35)),
        ScenePin(id: UUID(), name: "Headphones", locationNote: "Beside the monitor", normalizedPoint: CGPoint(x: 0.72, y: 0.62)),
    ]
}
