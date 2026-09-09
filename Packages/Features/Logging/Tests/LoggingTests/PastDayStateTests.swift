import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

// `FR-17.7`'s past *day*, split from `PastSessionStateTests.swift` at SwiftLint's file ceiling:
// that file is the screen as `FR-1.2.7` left it, and this is the shape `D-17.6` gave it.

/// A past session drawn as a *day* (`FR-17.7.3`, `FR-17.7.6`, `FR-15.3.1`, `FR-15.3.3`).
@Suite("Past session as a day")
struct PastSessionDayTests {
    @Test("The stamp chooses the shape, not the presence of a plan — FR-17.7.6")
    func theStampChoosesTheShape() async throws {
        let free = try await PastSession.logged(names: ["Back Squat"])
        // A plan without a stamp: a workout started from a routine outside a program.
        try await free.plan(at: 0)
        await free.state.load()
        #expect(free.state.isPlannedDay == false)

        let day = try await PastSession.logged(names: ["Back Squat"], stamped: true)
        await day.state.load()
        // No plan at all, and still a day: the lifter replaced every exercise on it.
        #expect(day.state.exercises.allSatisfy { $0.planned.isEmpty })
        #expect(day.state.isPlannedDay)
    }

    @Test("The exercises carry what was planned for them — FR-15.3.1")
    func exercisesCarryTheirPlan() async throws {
        let past = try await PastSession.logged(names: ["Back Squat", "Bench Press"], stamped: true)
        try await past.plan(at: 0, weight: Weight(grams: 140_000), reps: 5, sets: 5)
        try await past.logSet(at: 0, order: 0, weight: Weight(grams: 140_000))

        await past.state.load()

        #expect(past.state.exercises[0].planned.count == 1)
        #expect(past.state.exercises[0].planned[0].targetWeight == Weight(grams: 140_000))
        #expect(past.state.exercises[0].planned[0].targetSets == 5)
        // FR-15.3.1's per-set target comes free once the plan is populated.
        let logged = try #require(past.state.exercises[0].sets.first)
        #expect(past.state.exercises[0].plannedTargets[logged.id]?.targetReps == 5)
        // An exercise nobody planned carries none, which is not a state anything reports.
        #expect(past.state.exercises[1].planned.isEmpty)
    }

    @Test("Adherence is 4 of 21 over the review's walk, and nil for a free workout — FR-15.3.3")
    func adherenceIsReported() async throws {
        let past = try await PastSession.logged(
            names: ["Back Squat", "Bench Press", "Barbell Row"], stamped: true)
        // 5 + 5 + 11 = 21 prescribed sets.
        try await past.plan(at: 0, reps: 5, sets: 5)
        try await past.plan(at: 1, reps: 8, sets: 5)
        try await past.plan(at: 2, reps: 10, sets: 11)
        // Four of them performed as prescribed, and a fifth a rep short.
        for order in 0..<4 { try await past.logSet(at: 0, order: order, reps: 5) }
        try await past.logSet(at: 0, order: 4, reps: 4)

        await past.state.load()

        let adherence = try #require(past.state.adherence)
        #expect(adherence.asPrescribed == 4)
        #expect(adherence.prescribed == 21)

        let free = try await PastSession.logged(names: ["Back Squat"])
        try await free.logSet(at: 0, order: 0)
        await free.state.load()
        #expect(free.state.adherence == nil)
    }

    @Test("A day still being answered reports no adherence — FR-17.7.3's 'once the day is done'")
    func adherenceWaitsForTheDayToEnd() async throws {
        let past = try await PastSession.logged(
            names: ["Back Squat"], stamped: true, isFinished: false)
        try await past.plan(at: 0, reps: 5, sets: 5)
        try await past.logSet(at: 0, order: 0, reps: 5)

        await past.state.load()

        // The plan is read and the ratio would be computable; it is withheld because a day with
        // rows nobody has reached would report a figure that rises as the work is done.
        #expect(past.state.exercises[0].planned.count == 1)
        #expect(past.state.adherence == nil)
    }

    @Test("A skipped row counts against adherence, its prescribed sets standing — FR-15.3.4")
    func aSkippedRowCostsAdherence() async throws {
        let past = try await PastSession.logged(
            names: ["Back Squat", "Bench Press"], stamped: true)
        try await past.plan(at: 0, reps: 5, sets: 3)
        try await past.plan(at: 1, reps: 5, sets: 2)
        for order in 0..<3 { try await past.logSet(at: 0, order: order, reps: 5) }
        // Answered with nothing behind it, which is what a skip is (`TR-17.4`).
        try await past.markDone(at: 1)

        await past.state.load()

        let adherence = try #require(past.state.adherence)
        #expect(adherence.asPrescribed == 3)
        #expect(adherence.prescribed == 5)
        #expect(past.state.dayRows[1].answer == .skipped)
    }

    @Test("The rows are the checklist's own — a skip, an as-planned answer and an unanswered row")
    func theRowsAreTheChecklistRows() async throws {
        let past = try await PastSession.logged(
            names: ["Back Squat", "Bench Press", "Barbell Row"], stamped: true)
        try await past.plan(at: 0, weight: Weight(grams: 100_000), reps: 5, sets: 2)
        try await past.plan(at: 1, weight: Weight(grams: 60_000), reps: 5, sets: 1)
        try await past.plan(at: 2, weight: Weight(grams: 80_000), reps: 5, sets: 1)
        for order in 0..<2 {
            try await past.logSet(at: 0, order: order, weight: Weight(grams: 100_000), reps: 5)
        }
        try await past.markDone(at: 0)
        try await past.markDone(at: 1)

        await past.state.load()

        let rows = past.state.dayRows
        #expect(rows.count == 3)
        #expect(rows[0].answer == .logged)
        #expect(rows[0].wasAsPlanned)
        #expect(rows[1].answer == .skipped)
        #expect(rows[2].answer == .unanswered)
        // FR-17.7.6 draws the row read-only, and the circle is what read-only takes away; the row
        // itself still says it would offer one on the Train tab.
        #expect(rows[2].hasCircle)
    }

    @Test("A per-set note reaches the day's row, each distinct one once — FR-17.7.4")
    func perSetNotesReachTheRow() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"], stamped: true)
        try await past.logSet(at: 0, order: 0, notes: "Belt on")
        try await past.logSet(at: 0, order: 1, notes: "Belt on")
        try await past.logSet(at: 0, order: 2, notes: "Left knee")
        try await past.logSet(at: 0, order: 3, isWarmup: true, notes: "Bar only")

        await past.state.load()

        // The warmup's note is absent: warmups are not the work, and the Did line counts none.
        #expect(past.state.dayRows[0].notes == ["Belt on", "Left knee"])
    }

    @Test("A noted set shares a group with another carrying the same note — SetGrouping's grain")
    func aNotedSetCanShareAGroup() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"])
        try await past.logSet(at: 0, order: 0, notes: "Belt on")
        try await past.logSet(at: 0, order: 1, notes: "Belt on")
        try await past.logSet(at: 0, order: 2, notes: "Left knee")
        await past.state.load()

        let groups = SetNumbering.grouped(
            SetNumbering.numbered(past.state.exercises[0].sets))

        // Two groups, not three: the note is a compared field, so it is a SHARED field of a run —
        // which is why the collapsed line draws it and the member rows stay quiet, and why the
        // task's own premise ("a noted set never shares a group") is false.
        #expect(groups.count == 2)
        #expect(groups[0].count == 2)
        #expect(groups[0].record.notes == "Belt on")
        #expect(groups[1].count == 1)
    }

    @Test("An archived exercise still names the row it was lifted under — FR-1.1.5")
    func anArchivedExerciseKeepsItsName() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"], stamped: true)
        try await past.archiveExercise(at: 0)

        await past.state.load()

        #expect(past.state.exercises[0].exercise?.isArchived == true)
        #expect(past.state.exercises[0].exercise?.name == "Back Squat")
    }
}

/// The badge on a past session's sets (`FR-17.7.2`).
@Suite("Past session records")
struct PastSessionRecordTests {
    @Test("A set that holds the record is marked, and the cache is read once per exercise")
    func theRecordHoldingSetIsMarked() async throws {
        let past = try await PastSession.logged(names: ["Back Squat", "Bench Press"])
        let heaviest = try await past.logSet(
            at: 0, order: 0, weight: Weight(grams: 140_000), reps: 5)
        try await past.logSet(at: 0, order: 1, weight: Weight(grams: 100_000), reps: 5)
        await past.recomputer.setDidChange(inEntryID: past.entries[0].id)

        await past.state.load()

        #expect(past.state.personalRecords.hasLoaded)
        #expect(!past.state.personalRecords.schemes(forSetID: heaviest.id).isEmpty)
    }

    @Test("A run since beaten carries none — the cache's truth is 'holds it now' — FR-17.7.2")
    func aBeatenRunCarriesNoBadge() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"])
        let first = try await past.logSet(at: 0, order: 0, weight: Weight(grams: 100_000), reps: 5)
        await past.recomputer.setDidChange(inEntryID: past.entries[0].id)
        await past.state.load()
        #expect(!past.state.personalRecords.schemes(forSetID: first.id).isEmpty)

        // A heavier set at the same scheme, logged later against the same exercise.
        try await past.logSet(at: 0, order: 1, weight: Weight(grams: 150_000), reps: 5)
        await past.recomputer.setDidChange(inEntryID: past.entries[0].id)
        await past.state.load()

        #expect(past.state.personalRecords.schemes(forSetID: first.id).isEmpty)
    }
}

/// Editing a past day's answer through the Log sheet (`FR-17.7.5`).
@Suite("Past day edits")
struct PastDayEditTests {
    @Test("Reopening over an answered row rewrites the group rather than appending to it")
    func theAnswerIsRewritten() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"], stamped: true)
        try await past.plan(at: 0, weight: Weight(grams: 100_000), reps: 10, sets: 3)
        for order in 0..<3 {
            try await past.logSet(at: 0, order: order, weight: Weight(grams: 100_000), reps: 10)
        }
        try await past.markDone(at: 0)
        await past.state.load()
        let rowID = past.state.dayRows[0].id

        await past.state.log(rowID: rowID, group: .of(grams: 30_000, reps: 8, sets: 3))

        // Three rows, rewritten in place — not six.
        let stored = try await past.storedSets(at: 0).filter { $0.deletedAt == nil }
        #expect(stored.count == 3)
        #expect(stored.allSatisfy { $0.weight == Weight(grams: 30_000) && $0.reps == 8 })
        #expect(past.state.writeFailure == nil)
        // DOD-17.7's other half: the plan rows are untouched by an edit to what was performed.
        #expect(past.state.exercises[0].planned[0].targetWeight == Weight(grams: 100_000))
        #expect(past.state.exercises[0].planned[0].targetReps == 10)
    }

    @Test("A lowered count soft-deletes the tail, and the row is read back through the screen")
    func aLoweredCountLeavesTwoRows() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"], stamped: true)
        for order in 0..<3 { try await past.logSet(at: 0, order: order) }
        try await past.markDone(at: 0)
        await past.state.load()

        await past.state.log(
            rowID: past.state.dayRows[0].id, group: .of(grams: 100_000, reps: 5, sets: 2))

        #expect(past.state.exercises[0].sets.count == 2)
        #expect(past.state.dayRows[0].performed.map(\.sets) == [2])
    }

    @Test("An unanswered row on a day still open is answered and marked done — FR-17.9.3")
    func loggingAnUnansweredRowMarksItDone() async throws {
        let past = try await PastSession.logged(
            names: ["Back Squat"], stamped: true, isFinished: false)
        try await past.plan(at: 0, reps: 5, sets: 3)
        await past.state.load()
        #expect(past.state.dayRows[0].answer == .unanswered)

        await past.state.log(
            rowID: past.state.dayRows[0].id, group: .of(grams: 100_000, reps: 5, sets: 3))

        #expect(past.state.dayRows[0].answer == .logged)
        let entry = try #require(await past.storedEntry(at: 0))
        #expect(entry.isMarkedDone)
        // Every member is work that happened, or the answer would read back as Skipped (TR-17.4).
        #expect(past.state.exercises[0].sets.allSatisfy { $0.isCompleted })
    }

    @Test("A row the screen does not hold writes nothing, rather than rewriting one that exists")
    func anAbsentRowWritesNothing() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"], stamped: true)
        try await past.logSet(at: 0, order: 0)
        await past.state.load()

        await past.state.log(rowID: UUID(), group: .of(grams: 30_000, reps: 8, sets: 3))

        #expect(past.state.exercises[0].sets.count == 1)
        #expect(past.state.exercises[0].sets[0].weight == Weight(grams: 100_000))
        #expect(past.state.writeFailure == nil)
    }

    @Test("A refused write is a diagnostic beside the rows, and the answer stays as it was")
    func aRefusedRewriteLeavesTheRows() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"], stamped: true)
        try await past.logSet(at: 0, order: 0)
        try await past.markDone(at: 0)
        let double = FailableWorkoutRepository(wrapping: past.repositories.workouts)
        let state = PastSession.state(
            sessionID: past.sessionID, over: past.repositories, workouts: double)
        await state.load()
        await double.refuseWrites()

        await state.log(rowID: state.dayRows[0].id, group: .of(grams: 30_000, reps: 8, sets: 1))

        #expect(state.writeFailure != nil)
        #expect(state.exercises[0].sets[0].weight == Weight(grams: 100_000))
    }

    @Test("An edit from a past day announces, so the records follow it — FR-1.6.4")
    func aPastDayEditAnnounces() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"], stamped: true)
        try await past.logSet(at: 0, order: 0, weight: Weight(grams: 100_000), reps: 5)
        try await past.markDone(at: 0)
        await past.recomputer.setDidChange(inEntryID: past.entries[0].id)
        await past.state.load()
        let before = try #require(past.state.exercises[0].sets.first)
        #expect(!past.state.personalRecords.schemes(forSetID: before.id).isEmpty)

        // The same row corrected down: SetGroupRewrite announces, so the cache no longer claims a
        // 100 kg record for an exercise whose only set is now 60 kg.
        await past.state.log(rowID: past.state.dayRows[0].id, group: .of(grams: 60_000, reps: 5, sets: 1))
        await past.state.load()

        let after = try #require(past.state.exercises[0].sets.first)
        let cells = try await past.repositories.personalRecords.personalRecords(
            forExerciseID: past.exercises[0].id, includingDeleted: false)
        #expect(cells.allSatisfy { $0.weight == Weight(grams: 60_000) })
        #expect(!past.state.personalRecords.schemes(forSetID: after.id).isEmpty)
    }

    @Test("A row already answered is not re-marked, so no local no-op outranks a remote edit")
    func anAnsweredRowIsNotReMarked() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"], stamped: true)
        try await past.logSet(at: 0, order: 0)
        try await past.markDone(at: 0)
        await past.state.load()
        let before = try #require(await past.storedEntry(at: 0)).updatedAt

        await past.state.log(
            rowID: past.state.dayRows[0].id, group: .of(grams: 60_000, reps: 5, sets: 1))

        // The sets moved, so the write happened; the entry did not, because it was already done.
        // `updatedAt` is `G-2.4`'s conflict key, and a mark rewritten to the value it holds would
        // let this correction outrank a real edit made on another device.
        #expect(past.state.exercises[0].sets[0].weight == Weight(grams: 60_000))
        let after = try #require(await past.storedEntry(at: 0))
        #expect(after.updatedAt == before)
    }

    @Test("The day ends when its last row is answered from here, as it does on the checklist")
    func answeringTheLastRowEndsTheDay() async throws {
        let past = try await PastSession.logged(
            names: ["Back Squat", "Bench Press"], stamped: true, isFinished: false)
        try await past.plan(at: 0, reps: 5, sets: 1)
        try await past.plan(at: 1, reps: 5, sets: 1)
        try await past.logSet(at: 0, order: 0, reps: 5)
        try await past.markDone(at: 0)
        await past.state.load()
        #expect(past.state.session?.endedAt == nil)
        #expect(past.state.adherence == nil)

        await past.state.log(
            rowID: past.state.dayRows[1].id, group: .of(grams: 100_000, reps: 5, sets: 1))

        // FR-17.9.8 is the day's rule wherever the answer comes from — and until it is written,
        // FR-17.7.3 withholds the adherence this screen exists to draw.
        #expect(past.state.session?.endedAt != nil)
        #expect(past.state.adherence != nil)
    }

    @Test("A day left with a row unanswered does not end, so a correction never finishes one")
    func correctingOneRowLeavesAnOpenDayOpen() async throws {
        let past = try await PastSession.logged(
            names: ["Back Squat", "Bench Press"], stamped: true, isFinished: false)
        try await past.logSet(at: 0, order: 0)
        try await past.markDone(at: 0)
        await past.state.load()

        await past.state.log(
            rowID: past.state.dayRows[0].id, group: .of(grams: 60_000, reps: 5, sets: 1))

        #expect(past.state.dayRows[1].answer == .unanswered)
        #expect(past.state.session?.endedAt == nil)
    }

    @Test("The group Log rewrites is the whole entry, warmups included — SetGroupRewrite's rule")
    func theGroupIsTheWholeEntryWarmupsIncluded() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"], stamped: true)
        for order in 0..<2 {
            try await past.logSet(at: 0, order: order, weight: Weight(grams: 40_000), isWarmup: true)
        }
        for order in 2..<4 { try await past.logSet(at: 0, order: order) }
        try await past.markDone(at: 0)
        await past.state.load()

        // The row draws the working sets only — `DayPerformance` counts no warmup — while the sheet
        // it opens carries all four, which is what makes the count the lifter lowers the entry's
        // and not the run's.
        #expect(past.state.dayRows[0].performed.map(\.sets) == [2])
        let row = try #require(past.state.editorRow(forRow: past.state.dayRows[0].id))
        #expect(row.logged.count == 4)

        await past.state.log(
            rowID: past.state.dayRows[0].id, group: .of(grams: 60_000, reps: 5, sets: 2))

        // Two rows, mapped position by position onto the first two stored — which are the warmups,
        // now demoted to work. Nothing here is a defect of this screen: it is the rewrite's own
        // documented rule, pinned so the interaction is asserted rather than incidental.
        #expect(past.state.exercises[0].sets.count == 2)
        #expect(past.state.exercises[0].sets.allSatisfy { !$0.isWarmup })
        #expect(past.state.exercises[0].sets.allSatisfy { $0.weight == Weight(grams: 60_000) })
    }

    @Test("What the sheet opens over is the row's plan and the sets already stored — FR-17.7.5")
    func theSheetOpensOverThePlanAndTheSets() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"], stamped: true)
        try await past.plan(at: 0, weight: Weight(grams: 100_000), reps: 10, sets: 3)
        try await past.logSet(at: 0, order: 0, reps: 8)
        await past.state.load()

        let row = try #require(past.state.editorRow(forRow: past.state.dayRows[0].id))
        #expect(row.plan.map(\.reps) == [10])
        #expect(row.plan.map(\.sets) == [3])
        #expect(row.logged.count == 1)
        #expect(row.logged[0].reps == 8)
        #expect(past.state.editorRow(forRow: UUID()) == nil)
    }
}

extension ResolvedSetGroup {
    /// A group of `sets` identical rows, which is what the Log sheet resolves to.
    ///
    /// - Parameters:
    ///   - grams: The load.
    ///   - reps: The repetitions.
    ///   - sets: How many.
    /// - Returns: The group.
    static func of(grams: Int, reps: Int, sets: Int) -> ResolvedSetGroup {
        let values = SetEntryValues(
            weight: Weight(grams: grams), reps: reps, rpe: nil, isWarmup: false, notes: "")
        return ResolvedSetGroup(
            values: values, sets: sets, rows: Array(repeating: values, count: sets))
    }
}
