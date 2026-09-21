import Foundation
import PowerliftingCore
import Testing

@testable import Logging

/// What a day row's overflow menu holds, and which resets ask first (`FR-17.9.3`, `FR-17.9.6`,
/// `FR-18.5.1`, `FR-18.5.2`).
///
/// **Here rather than over a rendering, for `SessionMenuContentsTests`' measured reason**: a menu
/// is readable from nothing. Its commands are not in a content snapshot — a snapshot pictures the
/// `⋯`, never what is behind it — and a hosted walk reaches them only by presenting a popover into
/// a window the host does not own. So *which item is there in which state* is a claim that has to
/// live in a value a test can construct, and `DayExerciseRow` computes exactly this one.
///
/// **What this cannot hold is the `role:`.** That **Reset to unanswered** is drawn destructive is a
/// property of the rendered `Button`, and a probe that dropped the role from the toolbar menu's
/// last item passed every test there (`T-18.09`). Held by review on this surface too.
@Suite("A day row's menu and its question")
struct DayRowMenuTests {
    // MARK: - The menu (FR-18.5.1)

    @Test("An unanswered row offers Log and Skip, and no way to reset an answer it has not given")
    func anUnansweredRow() {
        let contents = DayRowMenuContents(
            answer: .unanswered, offersSkip: true, offersReset: true)

        #expect(contents.items == [.log, .skip])
    }

    @Test("A skipped row offers Log and Reset")
    func aSkippedRow() {
        let contents = DayRowMenuContents(answer: .skipped, offersSkip: true, offersReset: true)

        #expect(contents.items == [.log, .reset])
    }

    @Test("A logged row offers Log and Reset")
    func aLoggedRow() {
        let contents = DayRowMenuContents(answer: .logged, offersSkip: true, offersReset: true)

        #expect(contents.items == [.log, .reset])
    }

    @Test("A past day's rows offer Log alone, answered or not")
    func aReadOnlySurface() {
        // `FR-17.7.6` and `OUT-18.10`: History passes neither handler, which is the whole of what
        // read-only means here — see ``DayExerciseRow/answer``.
        #expect(
            DayRowMenuContents(answer: .logged, offersSkip: false, offersReset: false).items
                == [.log])
        #expect(
            DayRowMenuContents(answer: .skipped, offersSkip: false, offersReset: false).items
                == [.log])
        #expect(
            DayRowMenuContents(answer: .unanswered, offersSkip: false, offersReset: false).items
                == [.log])
    }

    // MARK: - The question (FR-18.5.2)

    @Test("A row holding logged sets asks first, and names how many")
    func aLoggedRowAsks() throws {
        // Eight, over a *Did* line that reads six: two warmups went in with the work, a reset
        // removes them too, and the question names what the command does rather than what the row
        // draws.
        let row = Self.row(
            answer: .logged, performed: [Self.run(sets: 3), Self.run(sets: 3)], loggedSetCount: 8)

        let question = try #require(DayView.resetConfirmation(for: row))

        #expect(question.rowID == row.id)
        #expect(question.setCount == 8)
    }

    @Test("A skipped row resets without asking")
    func aSkippedRowDoesNotAsk() {
        // There is work to lose or there is not, and a skip lost none of it. The question exists
        // because the reset cannot be undone — the sets are soft-deleted and nothing in the app
        // brings one back — so a row with no sets has nothing to ask about.
        #expect(DayView.resetConfirmation(for: Self.row(answer: .skipped, performed: [])) == nil)
    }

    @Test("A row that reads skipped over completed warmups still asks")
    func aSkippedRowHoldingWarmupsAsks() throws {
        // Warmups are not the work, so the row derives as skipped — and they are still completed
        // sets a reset soft-deletes, which is what `FR-18.5.2` owes a question for.
        let row = Self.row(answer: .skipped, performed: [], loggedSetCount: 2)

        #expect(try #require(DayView.resetConfirmation(for: row)).setCount == 2)
    }

    /// One row, with only what these claims read.
    ///
    /// - Parameters:
    ///   - answer: What has been said about it.
    ///   - performed: The runs behind it.
    ///   - loggedSetCount: How many completed sets stand behind it, warmups included.
    /// - Returns: The row.
    private static func row(
        answer: DayRowAnswer, performed: [WeekPlanTarget], loggedSetCount: Int = 0
    ) -> DayRow {
        DayRow(
            id: UUID(),
            exercise: nil,
            plan: [],
            performed: performed,
            answer: answer,
            loggedSetCount: loggedSetCount)
    }

    /// One run of `sets` sets at the fixture load.
    ///
    /// - Parameter sets: How many.
    /// - Returns: The run.
    private static func run(sets: Int) -> WeekPlanTarget {
        WeekPlanTarget(id: UUID(), weight: Weight(grams: 100_000), reps: 5, sets: sets)
    }
}
