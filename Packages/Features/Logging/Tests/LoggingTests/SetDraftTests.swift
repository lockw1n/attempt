import Foundation
import PowerliftingCore
import Testing

@testable import Logging

/// What the set editor accepts, what it refuses, and what its ± controls do (`FR-1.2.3`,
/// `FR-1.2.5`, `FR-1.2.6`, `G-1.1`, `G-3.1`, `G-3.4`).
///
/// This is the crossing `TR-0.2.1`'s failable initializer was built for, and it is the first one in
/// the app: a keyboard on one side, whole grams on the other.
@Suite("Set draft")
struct SetDraftTests {
    // MARK: - The load (G-1.1, G-3.1)

    @Test("A typed kilogram value becomes whole grams")
    func weightInKilograms() {
        var draft = SetDraft(unit: .kilograms, locale: .posix)
        draft.weightText = "102.5"

        #expect(draft.weight == Weight(grams: 102_500))
    }

    @Test("The same digits mean a different load in pounds — the unit is the preference, not a label")
    func weightInPounds() {
        var kilograms = SetDraft(unit: .kilograms, locale: .posix)
        kilograms.weightText = "225"
        var pounds = SetDraft(unit: .pounds, locale: .posix)
        pounds.weightText = "225"

        #expect(kilograms.weight == Weight(grams: 225_000))
        #expect(pounds.weight == Weight(grams: 102_058))
    }

    @Test("A decimal comma is a decimal point where the locale writes it that way")
    func weightInAnotherLocale() {
        var draft = SetDraft(unit: .kilograms, locale: Locale(identifier: "de_DE"))
        draft.weightText = "102,5"

        #expect(draft.weight == Weight(grams: 102_500))
    }

    @Test("The wrong separator is refused, not silently truncated")
    func wrongSeparatorIsRefused() {
        // Observed in the simulator: lenient parsing takes the leading part it can finish, so a
        // point typed where the locale writes a comma logs 102 kg for a 102.5 kg set with nothing
        // saying so. A set that will not log is recoverable; a set logged wrong is not.
        var draft = SetDraft(unit: .kilograms, locale: Locale(identifier: "de_DE"))
        draft.weightText = "102.5"
        draft.repsText = "5"

        #expect(draft.weight == nil)
        #expect(draft.isLoggable == false)
    }

    @Test("An empty or unreadable load is no load, and the set does not go")
    func weightRefusals() {
        let blank = SetDraft(unit: .kilograms, locale: .posix)
        var words = blank
        words.weightText = "heavy"
        var spaces = blank
        spaces.weightText = "   "

        #expect(blank.weight == nil)
        #expect(words.weight == nil)
        #expect(spaces.weight == nil)
        #expect(blank.isLoggable == false)
    }

    @Test("A negative load is refused — Weight allows one, a load is not a delta")
    func negativeWeightIsRefused() {
        var pasted = SetDraft(unit: .kilograms, locale: .posix)
        pasted.weightText = "-100"
        pasted.repsText = "5"

        // `Weight` is signed on purpose and says so: it doubles as an increment or a deload, and
        // non-negativity is the caller's invariant. This crossing is the caller.
        #expect(pasted.weight == nil)
        #expect(pasted.isLoggable == false)
    }

    // MARK: - The repetitions (FR-1.2.5)

    @Test("Zero reps is a value, not an absence — it is what a failed set records")
    func zeroReps() {
        var draft = SetDraft(unit: .kilograms, locale: .posix)
        draft.weightText = "100"
        draft.repsText = "0"

        #expect(draft.reps == 0)
        #expect(draft.isLoggable == true)
    }

    @Test("Fractional and negative repetitions are refused")
    func repsRefusals() {
        var fractional = SetDraft(unit: .kilograms, locale: .posix)
        fractional.repsText = "5.5"
        var negative = SetDraft(unit: .kilograms, locale: .posix)
        negative.repsText = "-1"
        var blank = SetDraft(unit: .kilograms, locale: .posix)
        blank.repsText = ""

        #expect(fractional.reps == nil)
        #expect(negative.reps == nil)
        #expect(blank.reps == nil)
    }

    @Test("A repetition count too large for an Int is refused rather than trapping the process")
    func repsCeiling() {
        var atTheBoundary = SetDraft(unit: .kilograms, locale: .posix)
        // Int.max as a Double rounds up to 2^63, so a guard reading `<= Double(Int.max)` lets this
        // through and `Int(_:)` then traps. Nineteen digits is a reachable thing to type.
        atTheBoundary.repsText = "9223372036854775807"
        var beyond = SetDraft(unit: .kilograms, locale: .posix)
        beyond.repsText = "99999999999999999999"
        var ordinary = SetDraft(unit: .kilograms, locale: .posix)
        ordinary.repsText = "100"

        #expect(atTheBoundary.reps == nil)
        #expect(beyond.reps == nil)
        // Anchored to a literal, so the refusals above are not satisfied by everything refusing.
        #expect(ordinary.reps == 100)
    }

    // MARK: - The rating (FR-1.2.3)

    @Test("An empty RPE is a set that logs; a wrong one is a set that does not")
    func rpeIsOptionalButNotLax() {
        var draft = SetDraft(unit: .kilograms, locale: .posix)
        draft.weightText = "100"
        draft.repsText = "5"

        var rated = draft
        rated.rpeText = "8.5"
        var words = draft
        words.rpeText = "hard"
        var tooHigh = draft
        tooHigh.rpeText = "11"
        var tooLow = draft
        tooLow.rpeText = "0.5"

        #expect(draft.rpe == .absent)
        #expect(draft.isLoggable == true)
        #expect(draft.storedRPE == nil)
        #expect(rated.rpe == .value(8.5))
        #expect(rated.storedRPE == 8.5)
        #expect(rated.isLoggable == true)
        #expect(words.rpe == .invalid)
        #expect(words.isLoggable == false)
        #expect(tooHigh.rpe == .invalid)
        #expect(tooLow.rpe == .invalid)
    }

    @Test("Both ends of the scale are inside it")
    func rpeBounds() {
        var draft = SetDraft(unit: .kilograms, locale: .posix)
        var low = draft
        low.rpeText = "1"
        draft.rpeText = "10"

        #expect(low.rpe == .value(1))
        #expect(draft.rpe == .value(10))
    }

    // MARK: - Blank, which is not the same as wrong (FR-1.2.3)

    @Test("A form nobody has filled in is not a form filled in wrongly")
    func blankIsNotInvalid() {
        let blank = SetDraft(unit: .kilograms, locale: .posix)
        var spaces = blank
        spaces.weightText = "   "
        var typed = blank
        typed.rpeText = "18"
        // A stored row is allowed to carry a rating this form would not accept — that is deliberate,
        // so a row from a newer version survives being read. Repeating one arrives invalid through
        // no keystroke of the user's, and has to explain itself rather than open on a dead button.
        let repeated = SetDraft(
            repeating: SetEntryValues(weight: Weight(grams: 100_000), reps: 5, rpe: 47),
            unit: .kilograms,
            locale: .posix
        )

        #expect(blank.isBlank == true)
        #expect(spaces.isBlank == true)
        #expect(typed.isBlank == false)
        #expect(repeated.isBlank == false)
        #expect(repeated.isLoggable == false)
        // Both are unloggable; only one of them has nothing to say about it.
        #expect(blank.isLoggable == false)
    }

    // MARK: - The ± controls (NFR-1.3)

    @Test("One tap moves the load by the unit's display step, and a blank field starts at zero")
    func weightSteps() {
        let kilograms = SetDraft(unit: .kilograms, locale: .posix)
        let pounds = SetDraft(unit: .pounds, locale: .posix)

        #expect(kilograms.weightStep == 0.5)
        #expect(pounds.weightStep == 1)
        #expect(kilograms.adjustingWeight(by: 1).weightText == "0.5")
        #expect(pounds.adjustingWeight(by: 1).weightText == "1")
        #expect(kilograms.adjustingWeight(by: 4).weight == Weight(grams: 2_000))
    }

    @Test("The load floors at zero rather than going negative under the thumb")
    func weightFloor() {
        var draft = SetDraft(unit: .kilograms, locale: .posix)
        draft.weightText = "0.5"

        let once = draft.adjustingWeight(by: -1)
        let twice = once.adjustingWeight(by: -1)

        #expect(once.weightText == "0")
        #expect(twice.weightText == "0")
        #expect(twice.weight == Weight(grams: 0))
    }

    @Test("Repetitions step one at a time and floor at zero")
    func repsSteps() {
        var draft = SetDraft(unit: .kilograms, locale: .posix)
        draft.repsText = "1"

        #expect(draft.adjustingReps(by: 1).reps == 2)
        #expect(draft.adjustingReps(by: -1).reps == 0)
        #expect(draft.adjustingReps(by: -5).reps == 0)
        #expect(SetDraft(unit: .kilograms, locale: .posix).adjustingReps(by: 1).repsText == "1")
    }

    @Test("A stepped field is written without a grouping separator, so it can be typed into again")
    func steppedFieldStaysEditable() {
        var draft = SetDraft(unit: .kilograms, locale: Locale(identifier: "en_US"))
        draft.weightText = "1999.5"

        let stepped = draft.adjustingWeight(by: 1)

        #expect(stepped.weightText == "2000")
        #expect(stepped.weight == Weight(grams: 2_000_000))
    }

    // MARK: - The duplicate (FR-1.2.6)

    @Test("Repeating a set carries its load, reps and rating — and deliberately not its note")
    func repeatCarriesThreeFields() {
        let repeated = SetDraft(
            repeating: SetEntryValues(weight: Weight(grams: 102_500), reps: 5, rpe: 8),
            unit: .kilograms,
            locale: .posix
        )

        #expect(repeated.weightText == "102.5")
        #expect(repeated.repsText == "5")
        #expect(repeated.rpeText == "8")
        #expect(repeated.notes.isEmpty)
        #expect(repeated.isLoggable == true)
        #expect(repeated.weight == Weight(grams: 102_500))
    }

    @Test("Repeating an unrated set leaves the rating empty rather than inventing one")
    func repeatWithoutRating() {
        let repeated = SetDraft(
            repeating: SetEntryValues(weight: Weight(grams: 60_000), reps: 8, rpe: nil),
            unit: .kilograms,
            locale: .posix
        )

        #expect(repeated.rpeText.isEmpty)
        #expect(repeated.rpe == .absent)
        #expect(repeated.isLoggable == true)
    }

    @Test("A repeated set is shown in the unit the user reads in, not the one it was logged in")
    func repeatRendersInTheDisplayUnit() {
        let repeated = SetDraft(
            repeating: SetEntryValues(weight: Weight(grams: 100_000), reps: 5, rpe: nil),
            unit: .pounds,
            locale: .posix
        )

        #expect(repeated.weightText == "220.462")
        // Round-tripping through pounds costs less than a gram, which is the type's own claim.
        #expect(repeated.weight == Weight(grams: 100_000))
    }
}

extension Locale {
    /// The locale these tests read and write numbers in, so nothing here depends on the machine's.
    fileprivate static let posix = Locale(identifier: "en_US_POSIX")
}
