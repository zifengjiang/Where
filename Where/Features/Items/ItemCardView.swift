import SwiftUI

enum ItemCardSide: Equatable { case front, back }
enum ItemCardTransition: Equatable { case threeDFlip, opacity }
enum ItemCardAction: Equatable { case flipCard, fullNote }
enum ItemCardMetadataPlacement: Equatable { case card, fullNoteFooter }
struct ItemCardFaceActivation: Equatable {
    let allowsHitTesting: Bool
    let accessibilityHidden: Bool
}

struct ItemCardLayoutIdentity: Hashable, Sendable {
    let itemID: UUID
    let note: String
    let imageIdentity: String
    let size: CGSize
    let sizeCategory: UIContentSizeCategory

    init(itemID: UUID, note: String, imageIdentity: String = "", size: CGSize, sizeCategory: UIContentSizeCategory) {
        self.itemID = itemID; self.note = note; self.imageIdentity = imageIdentity; self.size = size; self.sizeCategory = sizeCategory
    }
}

struct ImmutableCGImage: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image.copy()! }
}

actor ItemCardLayoutCache {
    static let shared = ItemCardLayoutCache()
    private var values: [ItemCardLayoutIdentity: SilhouetteTextLayoutResult] = [:]
    private var tasks: [ItemCardLayoutIdentity: Task<SilhouetteTextLayoutResult, Never>] = [:]

    func result(for identity: ItemCardLayoutIdentity, compute: @escaping @Sendable () async -> SilhouetteTextLayoutResult) async -> SilhouetteTextLayoutResult {
        if let value = values[identity] { return value }
        if let task = tasks[identity] { return await task.value }
        let task = Task { await compute() }
        tasks[identity] = task
        let value = await task.value
        values[identity] = value
        tasks[identity] = nil
        return value
    }

    func cancel(_ identity: ItemCardLayoutIdentity) {
        tasks[identity]?.cancel()
        tasks[identity] = nil
    }
}

@MainActor final class ItemCardLayoutModel: ObservableObject {
    @Published private(set) var result: SilhouetteTextLayoutResult?
    @Published private(set) var identity: ItemCardLayoutIdentity?
    private let cache: ItemCardLayoutCache
    private var loadTask: Task<Void, Never>?
    private var requestedIdentity: ItemCardLayoutIdentity?

    init(cache: ItemCardLayoutCache = .shared) { self.cache = cache }
    func load(identity: ItemCardLayoutIdentity, compute: @escaping @Sendable () async -> SilhouetteTextLayoutResult) {
        let staleIdentity = requestedIdentity
        requestedIdentity = identity
        loadTask?.cancel(); result = nil
        loadTask = Task { [cache] in
            if let staleIdentity, staleIdentity != identity { await cache.cancel(staleIdentity) }
            let value = await cache.result(for: identity, compute: compute)
            guard !Task.isCancelled else { return }
            self.identity = identity; self.result = value
        }
    }
    deinit { loadTask?.cancel() }
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
    static func accessibilityHint(for action: ItemCardAction, side: ItemCardSide) -> String {
        switch action { case .flipCard: side == .back ? "Show image" : "Show note"; case .fullNote: "Open full note" }
    }

    static func createdAtText(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter(); formatter.locale = locale; formatter.timeZone = timeZone
        formatter.dateStyle = .medium; formatter.timeStyle = .short
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
    @StateObject private var layoutModel = ItemCardLayoutModel()

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
        let result = layoutModel.result
        let category = sizeCategory.uiKit
        let metrics = SilhouetteTextLayout.metrics(sizeCategory: category)
        let imageID = cutoutImage.cgImage.map { String(ObjectIdentifier($0).hashValue) } ?? "missing"
        let hasDateSpace = result.map { !$0.overflowed && ($0.lines.last?.rect.maxY ?? $0.path.boundingBox.minY) + 28 < $0.path.boundingBox.maxY } ?? false
        let identity = ItemCardLayoutIdentity(itemID: item.id, note: item.note ?? "", imageIdentity: imageID, size: size, sizeCategory: category)
        return ZStack(alignment: .bottom) {
            Canvas { context, _ in
                guard let result else { return }
                context.fill(Path(result.path), with: .color(Color(red: 0.96, green: 0.90, blue: 0.78)))
                for line in result.lines { context.draw(Text(line.text).font(.system(size: metrics.fontSize)).foregroundStyle(.black), in: line.rect) }
                if hasDateSpace {
                    context.draw(Text(ItemCardState.createdAtText(item.createdAt)).font(.caption2).foregroundStyle(.secondary),
                                 at: CGPoint(x: result.path.boundingBox.midX, y: result.path.boundingBox.maxY - 12))
                }
            }
            .contentShape(Rectangle()).onTapGesture { state.handle(.flipCard) }
            .accessibilityHint(ItemCardState.accessibilityHint(for: .flipCard, side: .back))
            if result?.overflowed == true || !hasDateSpace {
                Button(result?.overflowed == true ? "… More" : "Details") { state.handle(.fullNote) }
                    .font(.caption).buttonStyle(.borderedProminent).tint(.brown)
                    .accessibilityHint("Opens the full note without flipping the card")
            }
        }
        .task(id: identity) {
            guard let cgImage = cutoutImage.cgImage else { return }
            let immutable = ImmutableCGImage(cgImage)
            layoutModel.load(identity: identity) {
                await Task.detached {
                    SilhouetteTextLayout.layout(text: identity.note, alphaImage: immutable.image, canvasSize: identity.size,
                                                fontSize: metrics.fontSize, lineHeight: metrics.lineHeight, sizeCategory: category)
                }.value
            }
        }
        .onChange(of: result?.overflowed) { _, _ in state.noteOverflowed = (result?.overflowed ?? false) || !hasDateSpace }
        .accessibilityLabel("\(item.name), note: \(item.note ?? "No note"). \(ItemCardState.createdAtText(item.createdAt))")
        .accessibilityHint(ItemCardState.accessibilityHint(for: .flipCard, side: .back))
        .accessibilityAddTraits(.isButton)
    }
}

extension ContentSizeCategory {
    var uiKit: UIContentSizeCategory {
        switch self {
        case .extraSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .extraLarge: .extraLarge
        case .extraExtraLarge: .extraExtraLarge
        case .extraExtraExtraLarge: .extraExtraExtraLarge
        case .accessibilityMedium: .accessibilityMedium
        case .accessibilityLarge: .accessibilityLarge
        case .accessibilityExtraLarge: .accessibilityExtraLarge
        case .accessibilityExtraExtraLarge: .accessibilityExtraExtraLarge
        case .accessibilityExtraExtraExtraLarge: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}
