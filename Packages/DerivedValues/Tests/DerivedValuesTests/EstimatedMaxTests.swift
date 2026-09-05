import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues

/// `FR-1.7.1`'s estimate: the formula, the window, and the seven things it says when there is no
/// number.
@Suite("Estimated one-rep maximum")
struct EstimatedMaxTests {
    // MARK: - The number (FR-1.7.1, FR-1.7.2)

    /// The two reference values are `E1RMCalculatorTests`' own — Epley's 116,667 g for 100 kg × 5,
    /// and Brzycki's 36/32 of the same load. Cited rather than re-derived, per this task's brief.
    @Test("The estimate is the formula's answer for the best in-window set")
    func theEstimateIsTheFormulasAnswer() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: weeksAgo(1), sets: [working(100_000, 5)])

        let epley = try await recomputer(over: log, formula: .epley)
            .estimatedMax(forExerciseID: exerciseID)
        let brzycki = try await recomputer(over: log, formula: .brzycki)
            .estimatedMax(forExerciseID: exerciseID)

        #expect(epley.record?.weight == Weight(grams: 116_667))
        #expect(brzycki.record?.weight == Weight(grams: 112_500))
        #expect(epley.formula == .epley)
        #expect(brzycki.formula == .brzycki)
    }

    @Test("The estimate is dated from its source set's session, not from when the row was written")
    func theEstimateIsDatedFromItsSession() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: weeksAgo(1), sets: [working(100_000, 5)])

        let estimate = try await recomputer(over: log).estimatedMax(forExerciseID: exerciseID)

        #expect(estimate.record?.achievedAt == weeksAgo(1))
    }

    // MARK: - The window (FR-1.7.1)

    /// **The boundary exactly**, which is the one this task's checklist names. Ninety days back is
    /// inside; ninety-one is not — and the rep maxes prove the sets are all still there.
    @Test("A session on the window's own boundary is in, and a day older is out")
    func theWindowsBoundaryIsInclusive() async throws {
        let onEdge = try await estimate(daysAgo: 90)
        let pastEdge = try await estimate(daysAgo: 91)

        #expect(onEdge.record?.weight == Weight(grams: 116_667))
        #expect(pastEdge.record == nil)
        #expect(pastEdge.absence == .noneInWindow)
    }

    @Test("A rep max is all-time even where the estimate has gone stale")
    func theWindowDoesNotReachTheRepMaxes() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: daysAgo(200), sets: [working(100_000, 5)])

        let records = try await recomputer(over: log).recompute(forExerciseID: exerciseID)

        #expect(records.repMaxes.map(\.reps) == [1, 2, 3, 4, 5])
        #expect(records.bestE1RM == nil)
        #expect(records.estimate.absence == .noneInWindow)
    }

    @Test("A narrower window excludes a set the default one admits")
    func aNarrowerWindowExcludesMore() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: daysAgo(60), sets: [working(100_000, 5)])

        let wide = try await recomputer(over: log).estimatedMax(forExerciseID: exerciseID)
        let narrow = try await recomputer(over: log, lookback: E1RMLookback(days: 30))
            .estimatedMax(forExerciseID: exerciseID)

        #expect(wide.record != nil)
        #expect(narrow.record == nil)
        #expect(narrow.lookback.days == 30)
    }

    @Test("A discarded session's sets leave the window with it")
    func aDiscardedSessionIsOutOfTheWindow() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let entryID = try await log.session(
            of: exerciseID, on: weeksAgo(1), sets: [working(100_000, 5)])
        let entry = try #require(
            try await log.repositories.workouts.entry(id: entryID, includingDeleted: false))
        try await log.repositories.workouts.deleteSession(id: entry.sessionID)

        let estimate = try await recomputer(over: log).estimatedMax(forExerciseID: exerciseID)

        #expect(estimate.record == nil)
    }

    // MARK: - Why there is none (FR-1.13.3)

    @Test("An exercise nothing has been logged against says so, and does not blame the window")
    func nothingLoggedIsItsOwnReason() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()

        let estimate = try await recomputer(over: log).estimatedMax(forExerciseID: exerciseID)

        #expect(estimate.absence == .noSetsLogged)
    }

    @Test(
        "Each refusal is reported as itself",
        arguments: [
            (LoggedSet(grams: 100_000, reps: 5, isWarmup: true, isCompleted: true), E1RMRefusal.warmup),
            (LoggedSet(grams: 100_000, reps: 5, isWarmup: false, isCompleted: false), .incomplete),
            (LoggedSet(grams: -20_000, reps: 5, isWarmup: false, isCompleted: true), .assisted),
            (LoggedSet(grams: 100_000, reps: 12, isWarmup: false, isCompleted: true), .repsOutOfRange),
        ])
    func eachRefusalIsReported(set: LoggedSet, expected: E1RMRefusal) async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: weeksAgo(1), sets: [set])

        let estimate = try await recomputer(over: log).estimatedMax(forExerciseID: exerciseID)

        #expect(estimate.absence == .refused(expected))
    }

    /// `RPEBased` is the one formula that declines a set it was actually asked about, and this is
    /// the case that separates "the calculator refused" from "the formula had nothing to say".
    @Test("A formula that declines is reported as declining, not as a guard")
    func aDecliningFormulaIsItsOwnReason() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: weeksAgo(1), sets: [working(100_000, 5)])

        let estimate = try await recomputer(over: log, formula: .rpeBased)
            .estimatedMax(forExerciseID: exerciseID)

        #expect(estimate.absence == .refused(.formulaDeclined))
    }

    /// The nearest miss, not the commonest one: three warmups beside one twelve-rep working set is
    /// a lifter who needs to be told about the rep range.
    @Test("The reason named is the set that got furthest")
    func theNearestMissWins() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(
            of: exerciseID,
            on: weeksAgo(1),
            sets: [
                LoggedSet(grams: 60_000, reps: 5, isWarmup: true, isCompleted: true),
                LoggedSet(grams: 70_000, reps: 5, isWarmup: true, isCompleted: true),
                LoggedSet(grams: 100_000, reps: 12, isWarmup: false, isCompleted: true),
            ])

        let estimate = try await recomputer(over: log).estimatedMax(forExerciseID: exerciseID)

        #expect(estimate.absence == .refused(.repsOutOfRange))
    }

    /// **Out-of-window sets say nothing about the reason.** A lifter squatting properly last year
    /// and warming up last week is owed the warmup sentence, not "nothing recent" and not a reason
    /// drawn from work the estimate never looked at.
    @Test("The reason is drawn from the in-window sets alone")
    func theReasonIgnoresWorkOutsideTheWindow() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: daysAgo(200), sets: [working(100_000, 5)])
        try await log.session(
            of: exerciseID,
            on: weeksAgo(1),
            sets: [LoggedSet(grams: 60_000, reps: 5, isWarmup: true, isCompleted: true)])

        let estimate = try await recomputer(over: log).estimatedMax(forExerciseID: exerciseID)

        #expect(estimate.absence == .refused(.warmup))
    }

    // MARK: - What the window costs (NFR-1.6)

    /// **The trigger path must not read the window.** It runs behind every logged set, and the
    /// estimate it would compute is discarded — the cache holds rep maxes alone. The read is a
    /// ranged session query plus one entry read per session inside the window, so a lifter training
    /// four times a week would pay ~50 reads per set logged for a number nothing looks at.
    @Test("A logged set rewrites the cache without reading the lookback window")
    func theTriggerPathDoesNotReadTheWindow() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let entryID = try await log.session(
            of: exerciseID, on: weeksAgo(1), sets: [working(100_000, 5)])
        let counting = CountingWorkouts(wrapped: log.repositories.workouts)
        let subject = PersonalRecordRecomputer(
            workouts: counting,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        await counting.reset()

        await subject.setDidChange(inEntryID: entryID)

        #expect(await counting.exerciseWalks == 1)
        #expect(await counting.windowReads == 0)
    }

    /// The other half: a screen that actually wants the estimate does read it, so the assertion
    /// above is about *where* the read happens rather than about it having been dropped.
    @Test("Reading the estimate does read the lookback window")
    func readingTheEstimateReadsTheWindow() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: weeksAgo(1), sets: [working(100_000, 5)])
        let counting = CountingWorkouts(wrapped: log.repositories.workouts)
        let subject = PersonalRecordRecomputer(
            workouts: counting,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        await counting.reset()

        let estimate = try await subject.estimatedMax(forExerciseID: exerciseID)

        #expect(estimate.record != nil)
        #expect(await counting.windowReads == 1)
    }

    /// A cache miss on the records section is a rep-max read, and it walks for rep maxes alone.
    @Test("A cache miss recomputes the rep maxes without reading the window")
    func aCacheMissDoesNotReadTheWindow() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: weeksAgo(1), sets: [working(100_000, 5)])
        let counting = CountingWorkouts(wrapped: log.repositories.workouts)
        let subject = PersonalRecordRecomputer(
            workouts: counting,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        await counting.reset()

        let repMaxes = try await subject.repMaxes(forExerciseID: exerciseID)

        #expect(repMaxes.map(\.reps) == [1, 2, 3, 4, 5])
        #expect(await counting.windowReads == 0)
    }

    // MARK: - The settings triggers (FR-1.7.3)

    @Test("A window change tells every screen to read again")
    func aWindowChangeIsAnnounced() async throws {
        let subject = try await recomputer(over: TrainingLog())
        var changes = await subject.changes().makeAsyncIterator()

        await subject.lookbackDidChange(to: E1RMLookback(days: 30))

        #expect(await changes.next() == .everyExercise)
        #expect(await subject.lookbackInForce() == E1RMLookback(days: 30))
    }

    @Test("A window that is already in force announces nothing")
    func anUnchangedWindowIsSilent() async throws {
        let subject = try await recomputer(over: TrainingLog())
        var changes = await subject.changes().makeAsyncIterator()

        await subject.lookbackDidChange(to: .default)
        await subject.lookbackDidChange(to: E1RMLookback(days: 30))

        // The first call published nothing, so the first value read is the second call's.
        #expect(await changes.next() == .everyExercise)
    }

    // MARK: - Fixtures

    /// A recomputer over `log`, with "now" pinned to the fixture reference.
    private func recomputer(
        over log: TrainingLog,
        formula: E1RMFormulaID = .defaultFormula,
        lookback: E1RMLookback = .default
    ) async throws -> PersonalRecordRecomputer {
        PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            cache: log.repositories.personalRecords,
            formula: formula,
            lookback: lookback,
            now: { fixtureNow })
    }

    /// One 100 kg × 5 set, `daysAgo` days before the fixture's reference day.
    private func estimate(daysAgo days: Int) async throws -> EstimatedMax {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: daysAgo(days), sets: [working(100_000, 5)])
        return try await recomputer(over: log).estimatedMax(forExerciseID: exerciseID)
    }
}

/// The start of the day `days` before ``fixtureNow``.
///
/// **Deliberately not `E1RMLookback.earliest(from:)`.** A fixture that dated its sessions with the
/// window's own arithmetic would move whenever the window did, and a boundary asserted that way
/// cannot fail: measured, shifting `earliest` by a full day left all 71 tests green. This is
/// instead the arithmetic the *app* dates a session with — `Calendar.startOfDay`, as
/// `ActiveSessionStore` writes it — so the boundary here is the one a lifter can actually produce.
func daysAgo(_ days: Int) -> Date {
    let calendar = Calendar.autoupdatingCurrent
    let counted = calendar.date(byAdding: .day, value: -days, to: fixtureNow) ?? fixtureNow
    return calendar.startOfDay(for: counted)
}

/// The window itself, with no store behind it (`FR-1.7.1`).
@Suite("e1RM lookback window")
struct E1RMLookbackTests {
    @Test("The default is ninety days")
    func theDefaultIsNinetyDays() {
        #expect(E1RMLookback.default.days == 90)
    }

    /// Asserted against ``daysAgo(_:)``'s independent arithmetic rather than against
    /// `earliest(from:)`'s own answer, which is what makes an off-by-one in it visible here.
    @Test("The lower bound is the start of the day the window is named for")
    func theLowerBoundIsInclusive() {
        let window = E1RMLookback(days: 90)

        #expect(window.earliest(from: fixtureNow) == daysAgo(90))
        #expect(window.range(from: fixtureNow).contains(daysAgo(90)))
        #expect(!window.range(from: fixtureNow).contains(daysAgo(91)))
    }

    /// **The regression `startOfDay` closes.** A session is stored at midnight on its training day,
    /// so a bound carrying the hour it was measured at sits after every session on the boundary day
    /// and drops all of it — at every hour but midnight, which is to say always.
    @Test("The boundary day is admitted whatever hour it is now")
    func theBoundaryDayIsAdmittedFromAnyHour() {
        let calendar = Calendar.autoupdatingCurrent
        let lateInTheDay =
            calendar.date(bySettingHour: 23, minute: 30, second: 0, of: fixtureNow) ?? fixtureNow
        let boundaryDay = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -90, to: lateInTheDay) ?? lateInTheDay)

        #expect(E1RMLookback(days: 90).range(from: lateInTheDay).contains(boundaryDay))
    }

    /// A lookback is a floor on age, so nothing dated ahead of the clock falls out of it.
    @Test("There is no upper bound")
    func thereIsNoCeiling() {
        let window = E1RMLookback(days: 90)

        #expect(window.range(from: fixtureNow).contains(fixtureNow.addingTimeInterval(86_400)))
    }

    @Test("A window shorter than a day is a day")
    func aZeroWindowIsClamped() {
        #expect(E1RMLookback(days: 0).days == 1)
        #expect(E1RMLookback(days: -7).days == 1)
    }
}
