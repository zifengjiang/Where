import Foundation
import CoreGraphics
import Testing
import UIKit
import SwiftUI
@testable import Where

struct ItemCardStateTests {
    @Test func startsFrontAndToggles() {
        var state = ItemCardState(itemID: UUID())
        #expect(state.side == .front)
        state.flip()
        #expect(state.side == .back)
    }

    @Test func changingItemResetsFrontAndClosesNote() {
        var state = ItemCardState(itemID: UUID())
        state.flip(); state.showFullNote()
        state.select(itemID: UUID())
        #expect(state.side == .front)
        #expect(!state.isShowingFullNote)
    }

    @Test func transitionHonorsReduceMotion() {
        #expect(ItemCardState.transition(reduceMotion: false) == .threeDFlip)
        #expect(ItemCardState.transition(reduceMotion: true) == .opacity)
    }

    @Test func overflowIndicatorOpensFullNoteOnlyFromBack() {
        var state = ItemCardState(itemID: UUID())
        state.noteOverflowed = true
        state.showFullNote()
        #expect(!state.isShowingFullNote)
        state.flip(); state.showFullNote()
        #expect(state.isShowingFullNote)
    }

    @Test func createdAtFormattingIsLocaleStable() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: 4))!
        let value = ItemCardState.createdAtText(date, locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(value.hasPrefix("Recorded Jul 11, 2026"))
        #expect(value.contains("4:00"))
    }

    @Test func overflowButtonOpensSheetWithoutFlipping() {
        var state = ItemCardState(itemID: UUID())
        state.flip()
        state.noteOverflowed = true
        state.handle(.fullNote)
        #expect(state.side == .back)
        #expect(state.isShowingFullNote)
    }

    @Test func cardActionFlipsButDoesNotOpenSheet() {
        var state = ItemCardState(itemID: UUID())
        state.noteOverflowed = true
        state.handle(.flipCard)
        #expect(state.side == .back)
        #expect(!state.isShowingFullNote)
    }

    @Test func layoutIdentityTracksGeometryNoteAndDynamicType() {
        let id = UUID()
        let base = ItemCardLayoutIdentity(itemID: id, note: "a", size: CGSize(width: 200, height: 300), sizeCategory: .large)
        #expect(base != ItemCardLayoutIdentity(itemID: id, note: "b", size: base.size, sizeCategory: .large))
        #expect(base != ItemCardLayoutIdentity(itemID: id, note: "a", size: CGSize(width: 201, height: 300), sizeCategory: .large))
        #expect(base != ItemCardLayoutIdentity(itemID: id, note: "a", size: base.size, sizeCategory: .accessibilityLarge))
    }

    @Test func recordedTimeRoutesToFullNoteFooterWhenCardHasNoSpace() {
        #expect(ItemCardState.metadataPlacement(hasCardSpace: true) == .card)
        #expect(ItemCardState.metadataPlacement(hasCardSpace: false) == .fullNoteFooter)
    }

    @Test func onlyActiveFaceAcceptsInputAndVoiceOver() {
        let front = ItemCardState.faceActivation(face: .front, activeSide: .front)
        let hiddenBack = ItemCardState.faceActivation(face: .back, activeSide: .front)
        #expect(front.allowsHitTesting)
        #expect(!front.accessibilityHidden)
        #expect(!hiddenBack.allowsHitTesting)
        #expect(hiddenBack.accessibilityHidden)
    }

    @Test func accessibilityHintsMatchSeparateActions() {
        #expect(ItemCardState.accessibilityHint(for: .flipCard, side: .back) == "Show image")
        #expect(ItemCardState.accessibilityHint(for: .fullNote, side: .back) == "Open full note")
    }

    @MainActor @Test func cacheComputesOncePerIdentityAndDropsStalePublication() async {
        let cache = ItemCardLayoutCache()
        let model = ItemCardLayoutModel(cache: cache)
        let first = ItemCardLayoutIdentity(itemID: UUID(), note: "old", imageIdentity: "one", size: CGSize(width: 100, height: 100), sizeCategory: .large)
        let second = ItemCardLayoutIdentity(itemID: first.itemID, note: "new", imageIdentity: "one", size: first.size, sizeCategory: .large)
        let counter = LockedCounter()
        model.load(identity: first) {
            counter.increment(); try? await Task.sleep(for: .milliseconds(80)); return Self.stubResult(width: 10)
        }
        model.load(identity: second) {
            counter.increment(); return Self.stubResult(width: 20)
        }
        try? await Task.sleep(for: .milliseconds(150))
        #expect(model.identity == second)
        #expect(model.result?.path.boundingBox.width == 20)

        async let a = cache.result(for: second) { counter.increment(); return Self.stubResult(width: 30) }
        async let b = cache.result(for: second) { counter.increment(); return Self.stubResult(width: 30) }
        _ = await (a, b)
        #expect(counter.value == 2)
    }

    @Test func mapsEveryDynamicTypeSizeAndChangesCacheIdentity() {
        let cases: [(ContentSizeCategory, UIContentSizeCategory)] = [
            (.extraSmall, .extraSmall), (.small, .small), (.medium, .medium), (.large, .large),
            (.extraLarge, .extraLarge), (.extraExtraLarge, .extraExtraLarge), (.extraExtraExtraLarge, .extraExtraExtraLarge),
            (.accessibilityMedium, .accessibilityMedium), (.accessibilityLarge, .accessibilityLarge),
            (.accessibilityExtraLarge, .accessibilityExtraLarge), (.accessibilityExtraExtraLarge, .accessibilityExtraExtraLarge),
            (.accessibilityExtraExtraExtraLarge, .accessibilityExtraExtraExtraLarge),
        ]
        for (swiftUI, uiKit) in cases { #expect(swiftUI.uiKit == uiKit) }

        let id = UUID(), size = CGSize(width: 200, height: 200)
        let small = ItemCardLayoutIdentity(itemID: id, note: "note", size: size, sizeCategory: ContentSizeCategory.small.uiKit)
        let medium = ItemCardLayoutIdentity(itemID: id, note: "note", size: size, sizeCategory: ContentSizeCategory.medium.uiKit)
        #expect(small != medium)
    }

    private static func stubResult(width: CGFloat) -> SilhouetteTextLayoutResult {
        SilhouetteTextLayoutResult(path: CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 10), transform: nil), lines: [], overflowed: false, usesFallbackCard: false)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
