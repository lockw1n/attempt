import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Logging

/// A day row's hierarchy: which half of an answer is secondary, and which group a record badge
/// belongs to (`FR-18.3.6`, `FR-18.3.7`, `FR-18.3.8`, `DOD-18.15`).
///
/// **Over the value rather than over the row's `body`**, which is `T-18.14`'s measured reason:
/// swapping two arguments in a `View`'s body survived 662 tests, so *the planned lines are the
/// secondary ones* has to be a claim something can call. Every assertion here is on
/// ``DayRowScheme`` or on ``DayRow/recordBadges``.
@Suite("Day row hierarchy")
struct DayRowSchemeTests {
    // MARK: - Which half is which (FR-18.3.6)

    @Test("An unanswered row's plan stays primary — it is still the fact read at the rack")
    func unansweredPlanIsPrimary() {
        #expect(DayRowScheme.unansweredEmphasis == .plan)
        #expect(DayRowScheme.unansweredEmphasis.color == .textPrimary)
        #expect(DayRowScheme.sections(for: Self.row(answer: .unanswered)).isEmpty)
    }

    @Test("A skipped row draws no labelled half, having no numbers to label")
    func skippedDrawsNoSections() {
        #expect(DayRowScheme.sections(for: Self.row(answer: .skipped)).isEmpty)
    }

    @Test("A row that departed from its plan draws Planned secondary above Did primary")
    func deviatedRowPartsTheTwoHalves() {
        let row = Self.deviated
        let sections = DayRowScheme.sections(for: row)

        #expect(sections.map(\.role) == [.planned, .did])
        #expect(sections.map(\.emphasis) == [.reference, .done])
        // The targets as well as the emphasis, because a section carrying the right colour over the
        // wrong numbers is the swap this value exists to make unwritable.
        #expect(sections.first?.targets == row.plan)
        #expect(sections.last?.targets == row.performed)
    }

    @Test("A row done exactly as planned is one primary half, not two")
    func asPlannedRowIsOneHalf() {
        let row = Self.asPlanned
        let sections = DayRowScheme.sections(for: row)

        #expect(sections.map(\.role) == [.asPlanned])
        #expect(sections.map(\.emphasis) == [.done])
        #expect(sections.first?.targets == row.performed)
    }

    @Test("A row the lifter added has no plan to be read against, so its one half is Did")
    func addedRowIsDidAlone() {
        let sections = DayRowScheme.sections(for: Self.addedAndLogged)

        #expect(sections.map(\.role) == [.did])
        #expect(sections.map(\.emphasis) == [.done])
    }

    @Test("Only the reference half is secondary; both primary emphases resolve alike")
    func theColourTableHasTwoEntries() {
        #expect(PlanSchemeEmphasis.plan.color == .textPrimary)
        #expect(PlanSchemeEmphasis.done.color == .textPrimary)
        #expect(PlanSchemeEmphasis.reference.color == .textSecondary)
    }

    @Test("A half's words and its green come from its role, so neither can be given to the other")
    func theLabelBelongsToTheRole() {
        #expect(!DayRowSchemeSection.Role.planned.carriesAnswer)
        #expect(DayRowSchemeSection.Role.did.carriesAnswer)
        #expect(DayRowSchemeSection.Role.asPlanned.carriesAnswer)
        #expect(
            Set(
                [DayRowSchemeSection.Role.planned, .did, .asPlanned].map {
                    String(localized: $0.label)
                }
            ).count == 3)
    }

    // MARK: - One badge per group (FR-18.3.8, F-22)

    @Test("Two groups that both set a record carry two badges, each naming its own scheme")
    func bothGroupsCarryTheirOwnBadge() {
        let badges = Self.twoGroups(
            first: [Self.mark(reps: 10, sets: 3)], second: [Self.mark(reps: 7, sets: 3)]
        ).recordBadges

        // Anchored to the scheme rather than to the count: a rule that kept the maximal mark over
        // the whole exercise also produces two entries here, and would put `10 × 3` on both.
        #expect(badges.map { $0?.scheme } == [RecordScheme(reps: 10, sets: 3), RecordScheme(reps: 7, sets: 3)])
    }

    @Test("One record among two groups lands on the group that set it, and the other stays bare")
    func theBadgeLandsOnItsOwnGroup() throws {
        let badges = Self.twoGroups(first: [], second: [Self.mark(reps: 7, sets: 3)]).recordBadges

        try #require(badges.count == 2)
        #expect(badges[0] == nil)
        #expect(badges[1]?.scheme == RecordScheme(reps: 7, sets: 3))
    }

    @Test("Two groups and no records carry no badges")
    func noRecordsNoBadges() {
        #expect(Self.twoGroups(first: [], second: []).recordBadges.allSatisfy { $0 == nil })
    }

    @Test("A one-group row is unchanged: one run, one badge")
    func oneGroupRowIsUnchanged() {
        let row = DayRow(
            id: UUID(),
            exercise: nil,
            plan: [Self.target(100_000, reps: 5, sets: 5)],
            performed: [Self.target(95_000, reps: 5, sets: 4)],
            answer: .logged,
            records: [[Self.mark(reps: 5, sets: 4)]])

        #expect(row.recordBadges.map { $0?.scheme } == [RecordScheme(reps: 5, sets: 4)])
    }

    @Test("A run holding several cells still carries one badge, at the maximal one")
    func oneRunIsStillOneBadge() {
        let row = Self.twoGroups(
            first: [Self.mark(reps: 10, sets: 1), Self.mark(reps: 10, sets: 3)], second: [])

        #expect(row.recordBadges.first??.scheme == RecordScheme(reps: 10, sets: 3))
    }

    @Test("A row whose records list is shorter than its runs answers for every run all the same")
    func badgesAreAsLongAsTheRuns() throws {
        let row = DayRow(
            id: UUID(),
            exercise: nil,
            plan: [],
            performed: [Self.target(57_000, reps: 10, sets: 3), Self.target(64_000, reps: 7, sets: 3)],
            answer: .logged,
            records: [[Self.mark(reps: 10, sets: 3)]])

        try #require(row.recordBadges.count == 2)
        #expect(row.recordBadges[1] == nil)
    }

    @Test("A Planned half carries no badges — a prescription holds no records")
    func thePlannedHalfIsBare() {
        let sections = DayRowScheme.sections(
            for: Self.twoGroups(
                first: [Self.mark(reps: 10, sets: 3)], second: [Self.mark(reps: 7, sets: 3)]))

        #expect(sections.first?.role == .planned)
        #expect(sections.first?.badges.isEmpty == true)
        #expect(sections.last?.badges.count == 2)
    }

    // MARK: - The cache was never wrong; the row under-reported it (F-22)

    @Test("The cache marks both runs and the row now keeps both — the data never lost one")
    func theRowKeepsEveryRunTheCacheMarked() {
        let first = UUID()
        let second = UUID()
        let entryID = UUID()
        var marks = SessionRecordMarks()
        marks.bySetID[first] = [Self.mark(reps: 10, sets: 3)]
        marks.bySetID[second] = [Self.mark(reps: 7, sets: 3)]
        marks.hasLoaded = true

        let firstRun = Self.run(
            id: first,
            entryID: entryID,
            target: Self.target(57_000, reps: 10, sets: 3),
            from: 0)
        let secondRun = Self.run(
            id: second,
            entryID: entryID,
            target: Self.target(64_000, reps: 7, sets: 3),
            from: 3)
        let row = DayRow.performed(
            Self.exercise(entryID: entryID, sets: firstRun + secondRun), marks: marks)

        // Both halves: the runs the row draws, and the mark each of them carries. A `flatMap` here
        // produced two marks against one *Did* line and the row drew the maximal one alone.
        #expect(row.performed.count == 2)
        #expect(row.records.map(\.count) == [1, 1])
        #expect(
            row.recordBadges.map { $0?.scheme }
                == [RecordScheme(reps: 10, sets: 3), RecordScheme(reps: 7, sets: 3)])
    }

    // MARK: - Fixtures

    /// `DOD-18.15`'s row, with each group's marks named.
    ///
    /// - Parameters:
    ///   - first: What the first group stands at.
    ///   - second: What the second does.
    /// - Returns: The row.
    private static func twoGroups(first: [SchemeMark], second: [SchemeMark]) -> DayRow {
        DayRow(
            id: UUID(),
            exercise: nil,
            plan: [target(57_000, reps: 10, sets: 3), target(64_000, reps: 8, sets: 3)],
            performed: [target(57_000, reps: 10, sets: 3), target(64_000, reps: 7, sets: 3)],
            answer: .logged,
            records: [first, second])
    }

    /// A row in one of the three answers, with a plan and nothing performed.
    ///
    /// - Parameter answer: What has been said about it.
    /// - Returns: The row.
    private static func row(answer: DayRowAnswer) -> DayRow {
        DayRow(
            id: UUID(), exercise: nil, plan: [target(100_000, reps: 5, sets: 5)], answer: answer)
    }

    /// A row logged one set short of its plan.
    private static var deviated: DayRow {
        DayRow(
            id: UUID(),
            exercise: nil,
            plan: [target(100_000, reps: 5, sets: 5)],
            performed: [target(95_000, reps: 5, sets: 4)],
            answer: .logged)
    }

    /// A row logged exactly as it was prescribed.
    private static var asPlanned: DayRow {
        DayRow(
            id: UUID(),
            exercise: nil,
            plan: [target(100_000, reps: 5, sets: 5)],
            performed: [target(100_000, reps: 5, sets: 5)],
            answer: .logged)
    }

    /// `FR-1.2.2`'s added row, answered.
    private static var addedAndLogged: DayRow {
        DayRow(
            id: UUID(),
            exercise: nil,
            plan: [],
            performed: [target(60_000, reps: 12, sets: 3)],
            answer: .logged)
    }

    /// One target group.
    ///
    /// - Parameters:
    ///   - grams: Its load.
    ///   - reps: Its reps.
    ///   - sets: How many sets of it.
    /// - Returns: The group.
    private static func target(_ grams: Int, reps: Int, sets: Int) -> WeekPlanTarget {
        WeekPlanTarget(id: UUID(), weight: Weight(grams: grams), reps: reps, sets: sets)
    }

    /// One cell, as a first performance.
    ///
    /// - Parameters:
    ///   - reps: The cell's reps.
    ///   - sets: Its sets.
    /// - Returns: The mark.
    private static func mark(reps: Int, sets: Int) -> SchemeMark {
        SchemeMark(scheme: RecordScheme(reps: reps, sets: sets), isFirstPerformance: true)
    }

    /// A run of equal sets, the first carrying `id` so the cache can name the run by it.
    ///
    /// - Parameters:
    ///   - id: The first set's identifier.
    ///   - entryID: The exercise they belong to.
    ///   - target: Their load, their reps, and how many of them.
    ///   - from: Where the run starts in the exercise's order.
    /// - Returns: The sets.
    private static func run(
        id: UUID, entryID: UUID, target: WeekPlanTarget, from: Int
    ) -> [SetEntry] {
        (0..<target.sets).map { offset in
            let stamp = Date(timeIntervalSince1970: 1_700_000_000)
            return SetEntry(
                id: offset == 0 ? id : UUID(),
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                entryID: entryID,
                order: from + offset,
                // Every target this suite builds names a load; the coalesce is the price of
                // reusing `WeekPlanTarget`, whose own load is optional by `FR-15.2.2`.
                weight: target.weight ?? Weight(grams: 0),
                reps: target.reps,
                rpe: nil,
                rir: nil,
                isWarmup: false,
                isCompleted: true,
                targetWeight: nil,
                targetReps: nil,
                modifiers: [],
                notes: "",
                completedAt: stamp)
        }
    }

    /// One exercise's worth of a session.
    ///
    /// - Parameters:
    ///   - entryID: Its entry.
    ///   - sets: What was logged against it.
    /// - Returns: The exercise.
    private static func exercise(entryID: UUID, sets: [SetEntry]) -> SessionExercise {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        return SessionExercise(
            entry: ExerciseEntry(
                id: entryID,
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                sessionID: UUID(),
                exerciseID: UUID(),
                order: 0,
                notes: "",
                isMarkedDone: true),
            exercise: nil,
            sets: sets)
    }
}
