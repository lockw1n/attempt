import Foundation
import PowerliftingCore
import Testing

@testable import Routines

@Suite("Routine target draft")
struct RoutineGroupDraftTests {
    /// The locale every case here is read in, so a run does not depend on the machine's.
    private let locale = Locale(identifier: "en_US_POSIX")

    // FR-15.2.2's whole distinction, one level below the editor: `weight(unit:locale:)` answers
    // `nil` to an empty field AND to a mistyped one, so a caller reading it alone would store a
    // typo as a deliberately blank target.
    @Test("An empty load is blank; an unparseable one is not")
    func blankIsNotUnparseable() {
        var blank = RoutineGroupDraft()
        blank.repsText = "5"
        blank.setsText = "3"
        #expect(blank.isBlankWeight)
        #expect(blank.isResolvable(unit: .kilograms, locale: locale))

        var mistyped = blank
        mistyped.weightText = "1o0"
        #expect(!mistyped.isBlankWeight)
        #expect(!mistyped.isResolvable(unit: .kilograms, locale: locale))
    }

    @Test("Whitespace alone is a blank load, not a mistyped one")
    func whitespaceIsBlank() {
        var draft = RoutineGroupDraft()
        draft.weightText = "   "
        draft.repsText = "5"
        draft.setsText = "3"

        #expect(draft.isBlankWeight)
        #expect(draft.isResolvable(unit: .kilograms, locale: locale))
    }

    // A prescribed zero is a plan to do nothing, unlike a LOGGED zero, which is FR-1.2.5's failed
    // set. The two readings of the same number are why this refusal lives here and not in Logging.
    @Test("Zero reps or zero sets is refused")
    func zeroCountsAreRefused() {
        var draft = RoutineGroupDraft()
        draft.weightText = "100"
        draft.repsText = "0"
        draft.setsText = "3"
        #expect(!draft.isResolvable(unit: .kilograms, locale: locale))

        draft.repsText = "5"
        draft.setsText = "0"
        #expect(!draft.isResolvable(unit: .kilograms, locale: locale))

        draft.setsText = "3"
        #expect(draft.isResolvable(unit: .kilograms, locale: locale))
    }

    // G-3.4: the number is read in the reader's locale, so a half-kilo typed where the decimal is
    // a comma is a number and the same string typed in en_US is not.
    @Test("A load is read in the field's own locale")
    func loadIsLocaleRead() {
        var draft = RoutineGroupDraft()
        draft.repsText = "5"
        draft.setsText = "3"
        draft.weightText = "102,5"

        let german = Locale(identifier: "de_DE")
        #expect(draft.isResolvable(unit: .kilograms, locale: german))
        #expect(draft.weight(unit: .kilograms, locale: german) == Weight(grams: 102_500))
        #expect(!draft.isResolvable(unit: .kilograms, locale: locale))
    }

    @Test("A load is read in the unit the lifter enters it in")
    func loadIsUnitRead() {
        var draft = RoutineGroupDraft()
        draft.repsText = "5"
        draft.setsText = "3"
        draft.weightText = "100"

        let kilograms = draft.weight(unit: .kilograms, locale: locale)
        let pounds = draft.weight(unit: .pounds, locale: locale)
        #expect(kilograms == Weight(grams: 100_000))
        #expect(pounds != kilograms)
        #expect(pounds != nil)
    }
}
