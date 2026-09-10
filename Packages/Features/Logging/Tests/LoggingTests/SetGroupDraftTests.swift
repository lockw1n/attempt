import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Logging

/// The Log sheet's third field and its per-set fold (`FR-17.1.1`, `FR-17.9.4`, `FR-17.7.5`).
///
/// **Every rule here would otherwise live in a `body`**, which is the one place no test can fail —
/// T-17.11's finding, applied before the fact: what a form is prefilled with, when the fold resets,
/// and what N sets resolve to are the three decisions this sheet is.
@Suite("The Log sheet's group")
struct SetGroupDraftTests {
    /// The plan `DOD-17.7` is written against: three sets of ten at 30 kg.
    private static let plan = [
        WeekPlanTarget(id: UUID(), weight: Weight(grams: 30_000), reps: 10, sets: 3)
    ]

    // MARK: - The Sets field (FR-17.1.1)

    @Test("The count is a field, floored at one by its ± pair and refused at zero when typed")
    func theCountIsFlooredByTheControlAndRefusedByHand() {
        var draft = SetDraft(unit: .kilograms, locale: .posix)
        draft.weightText = "100"
        draft.repsText = "5"

        #expect(draft.sets == 1)
        #expect(draft.adjustingSets(by: 3).sets == 4)
        // The pair floors: a lifter holding − does not reach zero.
        #expect(draft.adjustingSets(by: -5).sets == 1)

        // Typed, zero is refused rather than floored — a group of no sets is the row left
        // unanswered, and Skip is how that is said.
        draft.setsText = "0"
        #expect(draft.sets == nil)
        #expect(!draft.isLoggable)
        draft.setsText = "3"
        #expect(draft.isLoggable)
    }

    @Test("The count is not part of blankness, because the field opens holding a number")
    func theCountDoesNotMakeAFormNonBlank() {
        // Counted, every draft would be non-blank and a form nobody had filled in would open on a
        // refusal — `isWarmup`'s rule, one field further along.
        #expect(SetDraft(unit: .kilograms, locale: .posix).isBlank)
    }

    // MARK: - What N sets resolve to (NFR-17.3)

    @Test("A form with the fold closed resolves to N copies of itself")
    func aClosedFoldResolvesToCopies() throws {
        var draft = SetDraft(unit: .kilograms, locale: .posix)
        draft.weightText = "30"
        draft.repsText = "8"
        draft.setsText = "3"

        let group = try #require(draft.resolvedGroup)

        #expect(group.sets == 3)
        #expect(group.rows.count == 3)
        #expect(group.rows.allSatisfy { $0.reps == 8 })
        #expect(group.rows.allSatisfy { $0.weight == Weight(grams: 30_000) })
        #expect(group.values.reps == 8)
    }

    @Test("An open fold decides each row, and the load stays the group's")
    func anOpenFoldDecidesEachRow() throws {
        var draft = SetDraft(unit: .kilograms, locale: .posix)
        draft.weightText = "80"
        draft.repsText = "8"
        draft.setsText = "3"
        draft = draft.openingDetails()
        draft.details[2].repsText = "6"
        draft.details[0].isWarmup = true

        let group = try #require(draft.resolvedGroup)

        #expect(group.rows.map(\.reps) == [8, 8, 6])
        #expect(group.rows.map(\.isWarmup) == [true, false, false])
        // A different load is a different group, so the fold cannot move it and does not try.
        #expect(group.rows.allSatisfy { $0.weight == Weight(grams: 80_000) })
    }

    @Test("A per-set field that does not resolve refuses the whole form")
    func anUnresolvableEntryRefusesTheForm() {
        var draft = SetDraft(unit: .kilograms, locale: .posix)
        draft.weightText = "80"
        draft.repsText = "8"
        draft.setsText = "2"
        draft = draft.openingDetails()
        #expect(draft.isLoggable)

        draft.details[1].rpeText = "hard"
        #expect(!draft.isLoggable)
        #expect(draft.resolvedGroup == nil)

        // Out of range is a typo here, exactly as it is in the form's own field.
        draft.details[1].rpeText = "47"
        #expect(!draft.isLoggable)

        draft.details[1].rpeText = "8"
        #expect(draft.isLoggable)
    }

    // MARK: - The fold's prefill and its reset (FR-17.9.4)

    @Test("Opening the fold prefills every entry from the form")
    func openingPrefills() {
        var draft = SetDraft(unit: .kilograms, locale: .posix)
        draft.weightText = "80"
        draft.repsText = "8"
        draft.setsText = "3"
        draft.rpeText = "9"
        draft.notes = "belt on"
        draft.isWarmup = true
        draft.modifiers = [SetModifier(.belt)]

        let opened = draft.openingDetails()

        #expect(opened.details.count == 3)
        #expect(opened.details.allSatisfy { $0.repsText == "8" })
        #expect(opened.details.allSatisfy { $0.rpeText == "9" })
        #expect(opened.details.allSatisfy { $0.notes == "belt on" })
        #expect(opened.details.allSatisfy { $0.isWarmup })
        #expect(opened.details.allSatisfy { $0.modifiers == [SetModifier(.belt)] })
        // Closing discards them, which is what makes the fold an override rather than a form.
        #expect(opened.closingDetails().details.isEmpty)
    }

    @Test("Changing the reps or the count resets the entries, and only while the fold is open")
    func theEntriesResetWithTheForm() {
        var draft = SetDraft(unit: .kilograms, locale: .posix)
        draft.weightText = "80"
        draft.repsText = "8"
        draft.setsText = "3"
        draft = draft.openingDetails()
        draft.details[2].repsText = "6"

        draft.repsText = "5"
        let reset = draft.resettingDetails()

        #expect(reset.details.count == 3)
        // The kept 6 is a number the lifter changed and the sheet would otherwise have ignored.
        #expect(reset.details.allSatisfy { $0.repsText == "5" })

        // Raising the count rebuilds rather than appending blanks.
        let raised = reset.adjustingSets(by: 2)
        #expect(raised.details.count == 5)
        #expect(raised.details.allSatisfy { $0.repsText == "5" })

        // A closed fold has nothing to rebuild, which is what keeps this off every keystroke on a
        // free workout.
        var closed = SetDraft(unit: .kilograms, locale: .posix)
        closed.repsText = "5"
        #expect(closed.resettingDetails().details.isEmpty)
        #expect(closed.adjustingSets(by: 1).details.isEmpty)
    }

    // MARK: - What the form opens holding (FR-17.9.4, FR-17.7.5)

    @Test("An unanswered row opens on the plan, count included")
    func anUnansweredRowOpensOnThePlan() {
        let draft = SetDraft(
            answering: SetEditorRow(plan: Self.plan), unit: .kilograms, locale: .posix)

        #expect(draft.weightText == "30")
        #expect(draft.repsText == "10")
        #expect(draft.setsText == "3")
        // Closed: the plan says one thing about every set, so there is nothing to override.
        #expect(draft.details.isEmpty)
    }

    @Test("An answered row opens on what is stored, and the fold opens only where the sets differ")
    func anAnsweredRowOpensOnTheAnswer() throws {
        let uniform = SetDraft(
            answering: SetEditorRow(plan: Self.plan, logged: Self.logged([8, 8, 8])),
            unit: .kilograms,
            locale: .posix)
        let varied = SetDraft(
            answering: SetEditorRow(plan: Self.plan, logged: Self.logged([8, 8, 6])),
            unit: .kilograms,
            locale: .posix)

        // Not the plan's 10: a form that reopened on the plan would undo the deviation the lifter
        // came back to correct.
        #expect(uniform.repsText == "8")
        #expect(uniform.setsText == "3")
        #expect(uniform.details.isEmpty)

        #expect(varied.details.map(\.repsText) == ["8", "8", "6"])
        let rewritten = try #require(varied.resolvedGroup)
        #expect(rewritten.rows.map(\.reps) == [8, 8, 6])
    }

    @Test("A blank-weight plan opens with the load empty and the count filled in")
    func aBlankWeightPlanLeavesTheLoadOpen() {
        // `FR-15.2.2`: a zero there would assert a load nobody chose, which is the distinction that
        // requirement exists for — but the reps and the count are prescribed either way.
        let open = [WeekPlanTarget(id: UUID(), weight: nil, reps: 12, sets: 4)]

        let draft = SetDraft(answering: SetEditorRow(plan: open), unit: .kilograms, locale: .posix)

        #expect(draft.weightText.isEmpty)
        #expect(draft.repsText == "12")
        #expect(draft.setsText == "4")
        #expect(!draft.isLoggable)
    }

    @Test("A row the lifter added opens blank rather than on a plan it has not got")
    func anAddedRowOpensBlank() {
        let draft = SetDraft(answering: SetEditorRow(plan: []), unit: .kilograms, locale: .posix)

        #expect(draft.isBlank)
        #expect(draft.setsText == "1")
    }

    /// Three stored sets at one load, with the reps given.
    ///
    /// - Parameter reps: What each set recorded.
    /// - Returns: The rows, in order.
    private static func logged(_ reps: [Int]) -> [SetEntry] {
        reps.enumerated().map { index, count in
            SetEntry(
                id: UUID(),
                createdAt: .distantPast,
                updatedAt: .distantPast,
                deletedAt: nil,
                entryID: UUID(),
                order: index,
                weight: Weight(grams: 30_000),
                reps: count,
                rpe: nil,
                rir: nil,
                isWarmup: false,
                isCompleted: true,
                targetWeight: nil,
                targetReps: nil,
                modifiers: [],
                notes: "",
                completedAt: .distantPast)
        }
    }
}
