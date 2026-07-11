import SwiftUI

enum ItemCardSide: Equatable { case front, back }
enum ItemCardTransition: Equatable { case threeDFlip, opacity }
enum ItemCardAction: Equatable { case flipCard, fullNote }
enum ItemCardMetadataPlacement: Equatable { case card, fullNoteFooter }
struct ItemCardFaceActivation: Equatable {
    let allowsHitTesting: Bool
    let accessibilityHidden: Bool
}

struct ItemCardLayoutIdentity: Equatable {
    let itemID: UUID
    let note: String
    let size: CGSize
    let sizeCategory: UIContentSizeCategory
}

struct ItemCardState: Equatable {
    private(set) var itemID: UUID
    private(set) var side: ItemCardSide = .front
    var noteOverflowed = false
    private(set) var isShowingFullNote = false

    init(itemID: UUID) { self.itemID = itemID }
    mutating func flip() { side = side == .front ? .back : .front }
    mutating func select(itemID: UUID) { guard itemID != self.itemID else { return }; self.itemID = itemID; side = .front; isShowingFullNote = false; noteOverflowed = false }
    mutating func showFullNote() { if side == .back && noteOverflowed { isShowingFullNote = true } }
    mutating func handle(_ action: ItemCardAction) {
        switch action { case .flipCard: flip(); case .fullNote: showFullNote() }
    }
    mutating func dismissFullNote() { isShowingFullNote = false }
    static func transition(reduceMotion: Bool) -> ItemCardTransition { reduceMotion ? .opacity : .threeDFlip }
    static func metadataPlacement(hasCardSpace: Bool) -> ItemCardMetadataPlacement { hasCardSpace ? .card : .fullNoteFooter }
    static func faceActivation(face: ItemCardSide, activeSide: ItemCardSide) -> ItemCardFaceActivation {
        let isActive = face == activeSide
        return ItemCardFaceActivation(allowsHitTesting: isActive, accessibilityHidden: !isActive)
    }

    static func createdAtText(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter(); formatter.locale = locale; formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return "Recorded \(formatter.string(from: date))"
    }
}

struct ItemCardView: View {
    let item: ItemSummary
    let cutoutImage: UIImage
    var onEditNote: ((String) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sizeCategory) private var sizeCategory
    @State private var state: ItemCardState

    init(item: ItemSummary, cutoutImage: UIImage, onEditNote: ((String) -> Void)? = nil) {
        self.item = item; self.cutoutImage = cutoutImage; self.onEditNote = onEditNote
        _state = State(initialValue: ItemCardState(itemID: item.id))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                front
                    .opacity(state.side == .front ? 1 : 0)
                    .allowsHitTesting(state.side == .front)
                    .accessibilityHidden(state.side != .front)
                back(size: proxy.size)
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (0, 1, 0))
                    .opacity(state.side == .back ? 1 : 0)
                    .allowsHitTesting(state.side == .back)
                    .accessibilityHidden(state.side != .back)
            }
            .rotation3DEffect(.degrees(!reduceMotion && state.side == .back ? 180 : 0), axis: (0, 1, 0))
            .animation(reduceMotion ? .easeInOut(duration: 0.18) : .spring(duration: 0.45), value: state.side)
        }
        .onChange(of: item.id) { _, id in state.select(itemID: id) }
        .sheet(isPresented: Binding(get: { state.isShowingFullNote }, set: { if !$0 { state.dismissFullNote() } })) {
            NoteEditorView(initialText: item.note ?? "", isReadOnly: onEditNote == nil,
                           footer: ItemCardState.createdAtText(item.createdAt), onSave: onEditNote ?? { _ in })
        }
    }

    private var front: some View {
        Button { state.handle(.flipCard) } label: { Image(uiImage: cutoutImage).resizable().scaledToFit() }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.name), front")
            .accessibilityHint("Tap to show note")
            .accessibilityAddTraits(.isButton)
    }

    private func back(size: CGSize) -> some View {
        let result = cutoutImage.cgImage.map { SilhouetteTextLayout.layout(text: item.note ?? "", alphaImage: $0, canvasSize: size, fontSize: UIFont.preferredFont(forTextStyle: .body).pointSize, sizeCategory: sizeCategory.uiKit) }
        let hasDateSpace = result.map { !$0.overflowed && ($0.lines.last?.rect.maxY ?? $0.path.boundingBox.minY) + 28 < $0.path.boundingBox.maxY } ?? false
        let identity = ItemCardLayoutIdentity(itemID: item.id, note: item.note ?? "", size: size, sizeCategory: sizeCategory.uiKit)
        return ZStack(alignment: .bottom) {
            Canvas { context, _ in
                guard let result else { return }
                context.fill(Path(result.path), with: .color(Color(red: 0.96, green: 0.90, blue: 0.78)))
                for line in result.lines { context.draw(Text(line.text).font(.body).foregroundStyle(.black), in: line.rect) }
                if hasDateSpace {
                    context.draw(Text(ItemCardState.createdAtText(item.createdAt)).font(.caption2).foregroundStyle(.secondary),
                                 at: CGPoint(x: result.path.boundingBox.midX, y: result.path.boundingBox.maxY - 12))
                }
            }
            .contentShape(Rectangle()).onTapGesture { state.handle(.flipCard) }
            if result?.overflowed == true || !hasDateSpace {
                Button(result?.overflowed == true ? "… More" : "Details") { state.handle(.fullNote) }
                    .font(.caption).buttonStyle(.borderedProminent).tint(.brown)
                    .accessibilityHint("Opens the full note without flipping the card")
            }
        }
        .task(id: identity) { state.noteOverflowed = (result?.overflowed ?? false) || !hasDateSpace }
        .accessibilityLabel("\(item.name), note: \(item.note ?? "No note"). \(ItemCardState.createdAtText(item.createdAt))")
        .accessibilityHint(result?.overflowed == true ? "Tap to read the full note" : "Tap to show image")
        .accessibilityAddTraits(.isButton)
    }
}

private extension ContentSizeCategory {
    var uiKit: UIContentSizeCategory {
        switch self {
        case .accessibilityMedium: .accessibilityMedium
        case .accessibilityLarge: .accessibilityLarge
        case .accessibilityExtraLarge: .accessibilityExtraLarge
        case .accessibilityExtraExtraLarge: .accessibilityExtraExtraLarge
        case .accessibilityExtraExtraExtraLarge: .accessibilityExtraExtraExtraLarge
        default: .large
        }
    }
}
