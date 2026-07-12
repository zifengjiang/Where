import SwiftUI
import UIKit

struct ScenePinLayout: Equatable {
    static let anchorSize = CGSize(width: 44, height: 44)
    static let labelSpacing: CGFloat = 4

    let anchorCenter: CGPoint

    var anchorFrame: CGRect {
        CGRect(
            x: anchorCenter.x - Self.anchorSize.width / 2,
            y: anchorCenter.y - Self.anchorSize.height / 2,
            width: Self.anchorSize.width,
            height: Self.anchorSize.height
        )
    }

    func labelFrame(for labelSize: CGSize) -> CGRect {
        CGRect(
            x: anchorCenter.x - labelSize.width / 2,
            y: anchorFrame.maxY + Self.labelSpacing,
            width: labelSize.width,
            height: labelSize.height
        )
    }
}

enum ScenePinPresentation {
    static let hitTarget: CGFloat = 44
    static let normalDiameter: CGFloat = 20
    static let selectedDiameter: CGFloat = 28
}

struct ScenePinLabelLayout: Equatable {
    static func center(anchor: CGPoint, labelSize: CGSize, viewport: CGSize, margin: CGFloat = 8) -> CGPoint {
        let halfWidth = labelSize.width / 2
        let x = min(max(anchor.x, margin + halfWidth), max(margin + halfWidth, viewport.width - margin - halfWidth))
        let below = anchor.y + ScenePinLayout.anchorSize.height / 2 + ScenePinLayout.labelSpacing + labelSize.height / 2
        let above = anchor.y - ScenePinLayout.anchorSize.height / 2 - ScenePinLayout.labelSpacing - labelSize.height / 2
        let y = below + labelSize.height / 2 <= viewport.height - margin ? below : max(margin + labelSize.height / 2, above)
        return CGPoint(x: x, y: y)
    }
}

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

enum ScenePinInteraction: Equatable {
    enum Presentation: Equatable { case button, accessibilityElement }
    static func presentation(hasTapAction: Bool) -> Presentation {
        hasTapAction ? .button : .accessibilityElement
    }
}

struct ScenePhotoView: View {
    let image: UIImage
    let pins: [ScenePin]
    let selectedItemID: UUID?
    let imageAccessibilityLabel: String
    var onImageTap: ((CGPoint) -> Void)?
    var onPinTap: ((UUID) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let geometry = AspectFitGeometry(imageSize: image.size, containerSize: proxy.size)

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .accessibilityLabel(imageAccessibilityLabel)

                ForEach(pins) { pin in
                    let point = geometry.viewPoint(for: pin.normalizedPoint)
                    if let onPinTap {
                        Button { onPinTap(pin.id) } label: { marker(for: pin, selected: pin.id == selectedItemID) }
                            .buttonStyle(.plain)
                            .position(point)
                    } else {
                        marker(for: pin, selected: pin.id == selectedItemID)
                            .position(point)
                    }
                    if pin.id == selectedItemID {
                        let labelSize = CGSize(width: min(220, max(80, proxy.size.width - 16)), height: 58)
                        Text(pin.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(width: labelSize.width, height: labelSize.height)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .position(ScenePinLabelLayout.center(anchor: point, labelSize: labelSize, viewport: proxy.size))
                            .accessibilityHidden(true)
                    }
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
        ZStack {
            Circle()
                .fill(WhereTheme.pin)
                .frame(width: selected ? ScenePinPresentation.selectedDiameter : ScenePinPresentation.normalDiameter,
                       height: selected ? ScenePinPresentation.selectedDiameter : ScenePinPresentation.normalDiameter)
            Circle()
                .stroke(selected ? Color.white : Color.black.opacity(0.65), lineWidth: selected ? 3 : 2)
                .frame(width: selected ? ScenePinPresentation.selectedDiameter : ScenePinPresentation.normalDiameter,
                       height: selected ? ScenePinPresentation.selectedDiameter : ScenePinPresentation.normalDiameter)
        }
        .frame(width: ScenePinLayout.anchorSize.width, height: ScenePinLayout.anchorSize.height)
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
            Text("位于这个场景中")
        }
    }
}

#Preview("Portrait phone") {
    ScenePhotoView(
        image: ScenePhotoPreviewFixture.image,
        pins: ScenePhotoPreviewFixture.pins,
        selectedItemID: ScenePhotoPreviewFixture.pins.first?.id,
        imageAccessibilityLabel: "Room scene photo"
    )
    .frame(width: 393, height: 852)
    .background(.black)
}

#Preview("Landscape device") {
    ScenePhotoView(
        image: ScenePhotoPreviewFixture.image,
        pins: ScenePhotoPreviewFixture.pins,
        selectedItemID: ScenePhotoPreviewFixture.pins.last?.id,
        imageAccessibilityLabel: "Room scene photo"
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
