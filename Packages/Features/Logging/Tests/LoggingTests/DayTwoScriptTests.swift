import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Logging

/// `DOD-18.4` — the author's Day 2, from the accidental skip to a day answered correctly.
///
/// **The scenario is `F-09` and `F-11` in one script.** Six exercises, the second planned in two
/// groups; **Skip remaining** answers all six by accident; every row is then reset and answered by
/// its circle. The exit criterion is that this is reachable **without Reset day** — that command
/// would have thrown the day's workout away and started it again, which is the whole of what the
/// tester could not avoid.
///
/// **A walk rather than six assertions about one command**, because what it is about is the
/// composition: `skipRemaining` ends the day, and the first reset has to re-open it before the next
/// circle has anything to write into.
@MainActor
@Suite("The author's Day 2 (DOD-18.4)")
struct DayTwoScriptTests {
    @Test("A day skipped whole is reset row by row and answered as planned, without Reset day")
    func theDayIsRecoveredRowByRow() async throws {
        let fixture = try await WeekFixture(days: 1, exercisesPerDay: 6)
        // The second exercise is prescribed in two groups — the shape every Phase 1.7 fixture
        // lacked, and the one a row-by-row recovery has to carry through both of its runs.
        try await fixture.addLoadedGroup(day: 0, slot: 1)
        let store = fixture.activeStore()
        let day = fixture.dayStore(dayIndex: 0, store: store)
        await day.load()
        try #require(day.rows.count == 6)
        try #require(day.rows[1].plan.count == 2)

        await day.skipRemaining()

        try #require(day.rows.allSatisfy { $0.answer == .skipped })
        try #require(day.isDone)
        let sessionID = try await fixture.session(day: 0).id

        for rowID in day.rows.map(\.id) {
            await day.reset(rowID: rowID)
            #expect(day.rows.first { $0.id == rowID }?.answer == .unanswered)
            await day.answerAsPlanned(rowID: rowID)
        }

        #expect(day.progress.answered == 6)
        #expect(day.progress.isComplete)
        #expect(day.isDone)
        #expect(day.rows.allSatisfy { $0.answer == .logged })
        #expect(day.rows.allSatisfy { $0.wasAsPlanned })
        // Both groups of the second, in the plan's order — the claim a one-group fixture cannot
        // make.
        let second = try #require(day.rows[safe: 1])
        #expect(second.performed.map(\.sets) == [3, 2])
        #expect(second.performed.map(\.reps) == [5, 3])
        #expect(second.performed.map { $0.weight?.grams } == [100_000, 120_000])
        // **Reset day was never used**: that command soft-deletes the session (`FR-18.4.5`), so the
        // day ending on the workout it started with is the evidence it was not reached for.
        let ended = try await fixture.session(day: 0)
        #expect(ended.id == sessionID)
        #expect(ended.deletedAt == nil)
        let week = fixture.weekState()
        await week.load(openSession: nil)
        #expect(WeekFixture.days(of: week).first?.progress == .done(on: ended.date))
    }
}

extension Array {
    /// The element at `index`, or `nil` where there is none.
    ///
    /// - Parameter index: The position.
    /// - Returns: The element, or `nil`.
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
