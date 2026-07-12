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

enum ScenePinLabelPolicy {
    static func showsOverlay(isAccessibilitySize: Bool) -> Bool { !isAccessibilitySize }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
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
                    if pin.id == selectedItemID && ScenePinLabelPolicy.showsOverlay(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize) {
                        Text(pin.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: min(220, max(80, proxy.size.width - 16)))
                            .fixedSize(horizontal: false, vertical: true)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .position(
                                x: min(max(point.x, 48), max(48, proxy.size.width - 48)),
                                y: point.y > proxy.size.height / 2 ? max(32, point.y - 50) : min(proxy.size.height - 32, point.y + 50)
                            )
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
            if selected && differentiateWithoutColor {
                Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white)
            }
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

#Preview("竖屏") {
    ScenePhotoView(
        image: ScenePhotoPreviewFixture.image,
        pins: ScenePhotoPreviewFixture.pins,
        selectedItemID: ScenePhotoPreviewFixture.pins.first?.id,
        imageAccessibilityLabel: "房间场景照片"
    )
    .frame(width: 393, height: 852)
    .background(.black)
}

#Preview("横屏") {
    ScenePhotoView(
        image: ScenePhotoPreviewFixture.image,
        pins: ScenePhotoPreviewFixture.pins,
        selectedItemID: ScenePhotoPreviewFixture.pins.last?.id,
        imageAccessibilityLabel: "房间场景照片"
    )
    .frame(width: 852, height: 393)
    .background(.black)
}

#Preview("深色定位点") {
    ScenePhotoView(image: ScenePhotoPreviewFixture.image, pins: ScenePhotoPreviewFixture.pins,
                   selectedItemID: ScenePhotoPreviewFixture.pins.first?.id,
                   imageAccessibilityLabel: "房间场景照片")
        .frame(width: 393, height: 500).preferredColorScheme(.dark)
}

#Preview("辅助字号定位点") {
    ScenePhotoView(image: ScenePhotoPreviewFixture.image, pins: ScenePhotoPreviewFixture.pins,
                   selectedItemID: ScenePhotoPreviewFixture.pins.first?.id,
                   imageAccessibilityLabel: "房间场景照片")
        .frame(width: 393, height: 500).environment(\.dynamicTypeSize, .accessibility3)
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
        ScenePin(id: UUID(), name: "钥匙", locationNote: "左侧架子上", normalizedPoint: CGPoint(x: 0.25, y: 0.35)),
        ScenePin(id: UUID(), name: "耳机", locationNote: "显示器旁边", normalizedPoint: CGPoint(x: 0.72, y: 0.62)),
    ]
}
