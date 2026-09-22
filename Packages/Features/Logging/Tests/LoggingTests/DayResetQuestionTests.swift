import Foundation
import PowerliftingCore
import Testing

@testable import Logging

/// When **Reset day** stops to ask, and when it just goes (`FR-18.4.6`, `Q-18.14` at (b)).
///
/// **Here rather than over a rendering, for `DayRowMenuTests`' measured reason**: a confirmation
/// dialog's buttons belong to a window the host does not own, so neither a snapshot nor a hosted
/// walk can reach them. What is assertable is the decision itself — ``DayView/dayResetAsks(rows:note:)``
/// — and the two lines that call it are held by review.
///
/// **The clauses are asserted one at a time, each over a day quiet in every other respect.** A
/// fixture that skipped a row *and* logged a set would pass for a decision that had dropped either
/// clause, which is the whole failure these are shaped around.
@MainActor
@Suite("When Reset day asks (FR-18.4.6)")
struct DayResetQuestionTests {
    // MARK: - The day that holds nothing but its date

    @Test("A day nobody has answered has nothing to lose, so the reset goes straight through")
    func anUntouchedDayDoesNotAsk() {
        #expect(!DayView.dayResetAsks(rows: [Self.planned(), Self.planned()], note: ""))
        // A field holding a space is not prose anyone would miss — ``SessionNoteDraft/firstLine``
        // reads a note the same way.
        #expect(!DayView.dayResetAsks(rows: [Self.planned()], note: "  \n "))
    }

    // MARK: - The four things worth asking over (Q-18.14)

    @Test("A completed set asks, with no mark standing over it")
    func aCompletedSetAsks() {
        // The set and the mark are two clauses because they are two facts: this row has never been
        // checked off, and a reset would still soft-delete the sets behind it. The mark's own
        // clause is the next test, over a row holding no set at all.
        #expect(DayView.dayResetAsks(rows: [Self.planned(), Self.planned(loggedSetCount: 3)], note: ""))
    }

    @Test("A skipped row asks, though a reset of that row alone would not")
    func aSkippedRowAsks() {
        // `FR-18.5.2`'s rule is narrower on purpose — a row's reset removes that row's sets, and a
        // skip has none. The day's removes the whole workout, and what the lifter loses here is
        // having decided: five skips is an afternoon's decisions, not an empty day.
        #expect(DayView.dayResetAsks(rows: [Self.planned(answer: .skipped), Self.planned()], note: ""))
    }

    @Test("A row the lifter added asks, unanswered and empty")
    func anAddedRowAsks() {
        // `FR-1.2.2`: what it cost was finding the exercise, and a silent reset sends them back to
        // the catalogue for it.
        #expect(DayView.dayResetAsks(rows: [Self.planned(), Self.added()], note: ""))
    }

    @Test("A session note asks on its own")
    func aNoteAsks() {
        // The sharpest of the four: every other answer here is one tap from being given again, and
        // a sentence the lifter typed is not.
        #expect(DayView.dayResetAsks(rows: [Self.planned()], note: "left shoulder felt off"))
    }

    // MARK: - The day the store actually builds (DOD-18.16)

    @Test("A day dated from its menu asks nothing, over the rows the store builds for it")
    func theDatedDayDoesNotAsk() async throws {
        // The rows above are hand-made, so this is the half they cannot prove: that a *planned*
        // row really does arrive with a plan behind it and no mark, and therefore that the added
        // row's clause does not fire on every day of the week.
        let day = try await Self.datedDay()

        // Counted before the decision is asked, because an empty list satisfies every clause: this
        // test passes over a store that returned no rows at all, and then proves nothing about the
        // plan behind them. The fixture builds two.
        #expect(day.rows.count == 2)
        #expect(!DayView.dayResetAsks(rows: day.rows, note: day.note))
    }

    @Test("A note typed into the workout reaches the decision, over the store's own reading")
    func theDatedDayAsksOnceANoteIsTyped() async throws {
        // The note clause's test above hands the decision a literal, so this is the half it cannot
        // prove: that what the screen passes as `note:` is this workout's note and not some other
        // string. ``DayStore/note`` forced to `""` fails nothing else in this suite.
        let day = try await Self.datedDay()

        await day.store.saveNote("left shoulder felt off")

        #expect(day.note == "left shoulder felt off")
        #expect(DayView.dayResetAsks(rows: day.rows, note: day.note))
    }

    @Test("The same day, one row answered, asks")
    func theDatedDayAsksOnceAnswered() async throws {
        let day = try await Self.datedDay()

        await day.answerAsPlanned(rowID: try #require(day.rows.first).id)

        #expect(DayView.dayResetAsks(rows: day.rows, note: day.note))
    }

    /// A day of the fixture week, dated from its menu and otherwise untouched (`FR-18.7.1`).
    ///
    /// - Returns: The store, loaded and holding a session.
    /// - Throws: Whatever the fixture throws.
    private static func datedDay() async throws -> DayStore {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 2)
        let day = fixture.dayStore(dayIndex: 0, store: fixture.activeStore())
        await day.load()
        await day.changeDate(to: weekFixtureDay.addingTimeInterval(-86_400 * 3))
        try #require(day.isStarted)
        return day
    }

    /// One row of the plan, with only what this decision reads.
    ///
    /// - Parameters:
    ///   - answer: What has been said about it.
    ///   - loggedSetCount: How many completed sets stand behind it.
    /// - Returns: The row.
    private static func planned(
        answer: DayRowAnswer = .unanswered, loggedSetCount: Int = 0
    ) -> DayRow {
        DayRow(
            id: UUID(),
            exercise: nil,
            plan: [WeekPlanTarget(id: UUID(), weight: Weight(grams: 100_000), reps: 5, sets: 3)],
            answer: answer,
            loggedSetCount: loggedSetCount)
    }

    /// One row the lifter added (`FR-1.2.2`) — no plan behind it, and nothing said about it yet.
    ///
    /// - Returns: The row.
    private static func added() -> DayRow {
        DayRow(id: UUID(), exercise: nil, plan: [])
    }
}
