import Foundation
import RepositoryInterface
import Testing

/// `TR-17.5`'s query, on both subjects: the sessions one run stamped with one week.
///
/// **A suite of its own rather than a case in the ordering one**, because only one of these three
/// tests is about order — the other two are what the query *selects*, and selecting is where the
/// two implementations are written independently (a `#Predicate` on one side, a `filter` on the
/// other).
@Suite("Conformance — a program run's week")
struct ProgramWeekConformanceTests {
    /// The run and the week the fixtures below are stamped with.
    private static let run = SortedIDs.first

    @Test(
        "The week read returns that run's sessions for that week and nothing else",
        arguments: Subject.all)
    func theWeekReadIsScopedToTheRunAndTheWeek(_ subject: Subject) async throws {
        let repositories = try subject.make()
        try await repositories.workouts.save(
            sessionRecord(notes: "wanted", programRunID: Self.run, weekNumber: 2, dayIndex: 0))
        // The four near misses, one per column: another run, another week, a session no program
        // stamped at all, and — the one the other three cannot reach — THIS run with no week on
        // it. Both implementations promise a `nil` week never matches whatever its run, because
        // `nil` is a workout logged before a program stamped one (`FR-16.8.3`) rather than week
        // zero; without this row that promise is asserted by neither, the unstamped session being
        // excluded by the run clause alone.
        try await repositories.workouts.save(
            sessionRecord(notes: "other run", programRunID: SortedIDs.second, weekNumber: 2))
        try await repositories.workouts.save(
            sessionRecord(notes: "other week", programRunID: Self.run, weekNumber: 3))
        try await repositories.workouts.save(sessionRecord(notes: "unstamped"))
        try await repositories.workouts.save(
            sessionRecord(notes: "this run, no week", programRunID: Self.run, weekNumber: nil))

        let read = try await repositories.workouts.sessions(
            forProgramRunID: Self.run, week: 2, includingDeleted: false)

        #expect(read.map(\.notes) == ["wanted"])
    }

    @Test("The week read hides soft-deleted sessions unless asked", arguments: Subject.all)
    func theWeekReadRespectsTheDeletedFlag(_ subject: Subject) async throws {
        let repositories = try subject.make()
        try await repositories.workouts.save(
            sessionRecord(notes: "live", programRunID: Self.run, weekNumber: 1))
        // Deleted through the front door, not by saving a row that claims to be: a write's
        // `deletedAt` is the write path's, and this suite may only do what the protocols offer.
        try await repositories.workouts.save(
            sessionRecord(id: SortedIDs.second, notes: "gone", programRunID: Self.run, weekNumber: 1))
        try await repositories.workouts.deleteSession(id: SortedIDs.second)

        let live = try await repositories.workouts.sessions(
            forProgramRunID: Self.run, week: 1, includingDeleted: false)
        let all = try await repositories.workouts.sessions(
            forProgramRunID: Self.run, week: 1, includingDeleted: true)

        #expect(live.map(\.notes) == ["live"])
        #expect(Set(all.map(\.notes)) == ["live", "gone"])
    }

    @Test(
        "A week's sessions come back newest first, on the day then the start then the id",
        arguments: Subject.all)
    func theWeekReadIsOrdered(_ subject: Subject) async throws {
        let repositories = try subject.make()
        // Two days of one week logged on one date, which is the tie `sessions(in:)`'s key cannot
        // separate: only `startedAt` tells them apart, and only the id separates the pair that
        // shares that too.
        try await repositories.workouts.save(
            sessionRecord(
                id: SortedIDs.second,
                notes: "earliest",
                startedAt: fixtureCreatedAt,
                programRunID: Self.run,
                weekNumber: 1))
        try await repositories.workouts.save(
            sessionRecord(
                id: SortedIDs.third,
                notes: "tied",
                startedAt: fixtureCreatedAt,
                programRunID: Self.run,
                weekNumber: 1))
        try await repositories.workouts.save(
            sessionRecord(
                notes: "later same day",
                startedAt: fixtureCreatedAt + 60,
                programRunID: Self.run,
                weekNumber: 1))
        try await repositories.workouts.save(
            sessionRecord(
                date: fixtureCreatedAt + fixtureDay,
                notes: "newest day",
                startedAt: fixtureCreatedAt,
                programRunID: Self.run,
                weekNumber: 1))

        let read = try await repositories.workouts.sessions(
            forProgramRunID: Self.run, week: 1, includingDeleted: false)

        #expect(read.map(\.notes) == ["newest day", "later same day", "tied", "earliest"])
    }
}
