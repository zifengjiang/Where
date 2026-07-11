import Foundation
import Testing
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
        #expect(value == "Recorded Jul 11, 2026 at 4:00 AM")
    }
}
