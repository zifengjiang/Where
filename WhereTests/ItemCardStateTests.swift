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
        #expect(value.hasPrefix("记录于 Jul 11, 2026"))
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
        let base = ItemCardLayoutIdentity(itemID: id, note: "a", imageRevision: "cutout-v1", size: CGSize(width: 200, height: 300), sizeCategory: .large)
        #expect(base != ItemCardLayoutIdentity(itemID: id, note: "b", imageRevision: "cutout-v1", size: base.size, sizeCategory: .large))
        #expect(base != ItemCardLayoutIdentity(itemID: id, note: "a", imageRevision: "cutout-v1", size: CGSize(width: 201, height: 300), sizeCategory: .large))
        #expect(base != ItemCardLayoutIdentity(itemID: id, note: "a", imageRevision: "cutout-v1", size: base.size, sizeCategory: .accessibilityLarge))
        #expect(base != ItemCardLayoutIdentity(itemID: id, note: "a", imageRevision: "cutout-v2", size: base.size, sizeCategory: .large))
    }

    @Test func stableImageRevisionSeparatesAndReusesCacheEntries() async throws {
        let cache = ItemCardLayoutCache()
        let itemID = UUID(), size = CGSize(width: 100, height: 100)
        let first = ItemCardLayoutIdentity(itemID: itemID, note: "note", imageRevision: "cutout-v1", size: size, sizeCategory: .large)
        let second = ItemCardLayoutIdentity(itemID: itemID, note: "note", imageRevision: "cutout-v2", size: size, sizeCategory: .large)
        let counter = LockedCounter()
        _ = try await cache.result(for: first) { counter.increment(); return Self.stubResult(width: 10) }
        _ = try await cache.result(for: second) { counter.increment(); return Self.stubResult(width: 20) }
        _ = try await cache.result(for: first) { counter.increment(); return Self.stubResult(width: 30) }
        #expect(counter.value == 2)
        #expect(await cache.value(for: first)?.path.boundingBox.width == 10)
        #expect(await cache.value(for: second)?.path.boundingBox.width == 20)
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
        #expect(ItemCardState.accessibilityHint(for: .flipCard, side: .back) == "显示物品照片")
        #expect(ItemCardState.accessibilityHint(for: .fullNote, side: .back) == "打开完整备忘")
    }

    @MainActor @Test func cacheComputesOncePerIdentityAndDropsStalePublication() async {
        let cache = ItemCardLayoutCache()
        let model = ItemCardLayoutModel(cache: cache)
        let first = ItemCardLayoutIdentity(itemID: UUID(), note: "old", imageRevision: "one", size: CGSize(width: 100, height: 100), sizeCategory: .large)
        let second = ItemCardLayoutIdentity(itemID: first.itemID, note: "new", imageRevision: "one", size: first.size, sizeCategory: .large)
        let counter = LockedCounter()
        model.load(identity: first) {
            counter.increment(); try? await Task.sleep(for: .milliseconds(80)); return Self.stubResult(width: 10)
        }
        model.load(identity: second) {
            counter.increment(); return Self.stubResult(width: 20)
        }
		for _ in 0..<100 where model.identity != second {
			try? await Task.sleep(for: .milliseconds(10))
		}
        #expect(model.identity == second)
        #expect(model.result?.path.boundingBox.width == 20)

        model.load(identity: second) { counter.increment(); return Self.stubResult(width: 30) }
		for _ in 0..<50 where counter.value != 2 {
			try? await Task.sleep(for: .milliseconds(10))
		}
        #expect(counter.value == 2)
    }

    @MainActor @Test func staleComputationIsCancelledBeforeCompletion() async {
        let model = ItemCardLayoutModel(cache: ItemCardLayoutCache())
        let old = ItemCardLayoutIdentity(itemID: UUID(), note: "old", imageRevision: "one", size: CGSize(width: 100, height: 100), sizeCategory: .large)
        let fresh = ItemCardLayoutIdentity(itemID: old.itemID, note: "fresh", imageRevision: "one", size: old.size, sizeCategory: .large)
        let completed = LockedCounter()
        model.load(identity: old) {
            for _ in 0..<100 { try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(5)) }
            completed.increment(); return Self.stubResult(width: 10)
        }
        try? await Task.sleep(for: .milliseconds(20))
        model.load(identity: fresh) { Self.stubResult(width: 20) }
		for _ in 0..<100 where model.identity != fresh {
			try? await Task.sleep(for: .milliseconds(10))
		}
        #expect(completed.value == 0)
        #expect(model.identity == fresh)
        #expect(model.result?.path.boundingBox.width == 20)
    }

    @Test func unresolvedLayoutShowsLoadingWithoutDetails() {
        let presentation = ItemCardLayoutPresentation(result: nil)
        #expect(presentation.isLoading)
        #expect(presentation.detailsTitle == nil)
        #expect(!presentation.canPresentFullNote)
    }

    @Test func resolvedOverflowShowsDetailsAndAllowsFullNote() {
        let presentation = ItemCardLayoutPresentation(result: Self.stubResult(width: 20, overflowed: true))
        #expect(!presentation.isLoading)
        #expect(presentation.detailsTitle == "查看完整备忘")
        #expect(presentation.canPresentFullNote)

        var state = ItemCardState(itemID: UUID())
        state.flip()
        state.noteOverflowed = presentation.canPresentFullNote
        state.handle(.fullNote)
        #expect(state.isShowingFullNote)
    }

    @MainActor @Test func imageWithoutCGImageBackingResolvesFallbackLayout() async {
        let image = UIImage(ciImage: CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 20, height: 20)))
        #expect(image.cgImage == nil)
        let model = ItemCardLayoutModel(cache: ItemCardLayoutCache())
        let identity = ItemCardLayoutIdentity(itemID: UUID(), note: "fallback note", imageRevision: "ci-v1", size: CGSize(width: 120, height: 160), sizeCategory: .large)
        model.load(identity: identity, alphaImage: image.cgImage, fontSize: 14, lineHeight: 18, sizeCategory: .large)
		for _ in 0..<50 where model.result == nil {
			try? await Task.sleep(for: .milliseconds(10))
		}
        #expect(model.result?.usesFallbackCard == true)
        #expect(model.identity == identity)
    }

    @MainActor @Test func nilCGImagesWithDifferentStableRevisionsDoNotCollide() async {
        let cache = ItemCardLayoutCache()
        let model = ItemCardLayoutModel(cache: cache)
        let itemID = UUID(), size = CGSize(width: 120, height: 160)
        let first = ItemCardLayoutIdentity(itemID: itemID, note: "fallback", imageRevision: "ci-v1", size: size, sizeCategory: .large)
        let second = ItemCardLayoutIdentity(itemID: itemID, note: "fallback", imageRevision: "ci-v2", size: size, sizeCategory: .large)
        model.load(identity: first, alphaImage: nil, fontSize: 14, lineHeight: 18, sizeCategory: .large)
		for _ in 0..<50 {
			if await cache.value(for: first) != nil { break }
			try? await Task.sleep(for: .milliseconds(10))
		}
        model.load(identity: second, alphaImage: nil, fontSize: 14, lineHeight: 18, sizeCategory: .large)
		for _ in 0..<50 {
			if await cache.value(for: second) != nil { break }
			try? await Task.sleep(for: .milliseconds(10))
		}
        #expect(await cache.count == 2)
        #expect(await cache.value(for: first) != nil)
        #expect(await cache.value(for: second) != nil)
    }

    @Test func cacheEvictsLeastRecentlyUsedAndNeverExceedsCapacity() async {
        let cache = ItemCardLayoutCache(maxEntries: 2)
        let ids = (0..<3).map { ItemCardLayoutIdentity(itemID: UUID(), note: "\($0)", imageRevision: "revision-\($0)", size: CGSize(width: 10, height: 10), sizeCategory: .large) }
        for (index, id) in ids.enumerated() { await cache.insert(Self.stubResult(width: CGFloat(index + 1)), for: id) }
        #expect(await cache.count == 2)
        #expect(await cache.value(for: ids[0]) == nil)
        #expect(await cache.value(for: ids[1]) != nil)
        _ = await cache.value(for: ids[1])
        await cache.insert(Self.stubResult(width: 4), for: ids[0])
        #expect(await cache.value(for: ids[2]) == nil)
        #expect(await cache.count == 2)
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
        let small = ItemCardLayoutIdentity(itemID: id, note: "note", imageRevision: "one", size: size, sizeCategory: ContentSizeCategory.small.uiKit)
        let medium = ItemCardLayoutIdentity(itemID: id, note: "note", imageRevision: "one", size: size, sizeCategory: ContentSizeCategory.medium.uiKit)
        #expect(small != medium)
    }

    private static func stubResult(width: CGFloat, overflowed: Bool = false) -> SilhouetteTextLayoutResult {
        SilhouetteTextLayoutResult(path: CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 10), transform: nil), lines: [], overflowed: overflowed, usesFallbackCard: false)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
