import Foundation
import PowerliftingCore
import Testing

@testable import Settings

/// `FR-1.8.1`'s form, as the crossing between what is typed and what is stored.
@Suite("Bodyweight entry draft")
struct BodyweightEntryDraftTests {
    private static let day = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("An empty draft is blank, is refused, and says nothing yet")
    func emptyDraftIsBlank() {
        let draft = makeDraft()

        #expect(draft.isBlank)
        #expect(draft.refusal == .notAWeight)
        #expect(draft.isSavable == false)
        #expect(draft.entry() == nil)
    }

    @Test("A typed reading becomes grams, dated to the start of its day, from the user's own hand")
    func typedReadingBecomesAnEntry() throws {
        var draft = makeDraft()
        draft.weightText = "82.4"

        let entry = try #require(draft.entry())

        #expect(entry.weight == Weight(grams: 82_400))
        #expect(entry.source == .manual)
        #expect(entry.date == Calendar.gmt.startOfDay(for: Self.day))
        #expect(entry.deletedAt == nil)
        #expect(entry.id == draft.newEntryID)
    }

    @Test("The number is read in the user's locale, not against a decimal point")
    func numberIsReadInTheLocale() throws {
        var comma = makeDraft(locale: Locale(identifier: "de_DE"))
        comma.weightText = "82,4"
        #expect(try #require(comma.entry()).weight == Weight(grams: 82_400))

        // The same keystrokes in the other direction: a point is not a decimal separator there, so
        // the field is refused rather than read as 824 kg.
        var point = makeDraft(locale: Locale(identifier: "de_DE"))
        point.weightText = "82.4"
        #expect(point.refusal == .notAWeight)
    }

    @Test("A pounds field is read in pounds")
    func poundsAreReadInPounds() throws {
        var draft = makeDraft(unit: .pounds)
        draft.weightText = "180"

        // 180 lb is 81 646.6266 g, and the crossing rounds to the nearest gram (`G-1.1`).
        #expect(try #require(draft.entry()).weight == Weight(grams: 81_647))
    }

    @Test("Zero and a negative reading are both refused, and for different reasons")
    func zeroAndNegativeAreRefused() {
        var zero = makeDraft()
        zero.weightText = "0"
        #expect(zero.refusal == .notPositive)
        #expect(zero.entry() == nil)

        var negative = makeDraft()
        negative.weightText = "-80"
        #expect(negative.refusal == .notAWeight)
        #expect(negative.entry() == nil)
    }

    @Test("A field holding only spaces is blank, so the opening form does not scold")
    func whitespaceOnlyIsBlank() {
        var draft = makeDraft()
        draft.weightText = "   "

        // The trim is the whole of this: without it the form draws a refusal at a field the user
        // has typed nothing into.
        #expect(draft.isBlank)
        #expect(draft.refusal == .notAWeight)
        #expect(draft.isSavable == false)
    }

    @Test("Half a field is not a reading")
    func partialFieldIsRefused() {
        var draft = makeDraft()
        draft.weightText = "8 2"

        #expect(draft.refusal == .notAWeight)
        #expect(draft.isBlank == false)
    }

    @Test("Saving twice writes the same row rather than two")
    func identityIsStableAcrossSaves() throws {
        var draft = makeDraft()
        draft.weightText = "82"

        let first = try #require(draft.entry())
        let second = try #require(draft.entry())

        #expect(first.id == second.id)
    }

    /// A draft over a fixed day, so nothing here depends on when it runs.
    private func makeDraft(
        unit: MassUnit = .kilograms,
        locale: Locale = Locale(identifier: "en_US")
    ) -> BodyweightEntryDraft {
        BodyweightEntryDraft(unit: unit, locale: locale, calendar: .gmt, day: Self.day)
    }
}
