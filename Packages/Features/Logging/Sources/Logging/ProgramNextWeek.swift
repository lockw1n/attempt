import Foundation
import RepositoryInterface

/// `FR-17.8.4`'s **Start next week**: the week's days rewritten from how each exercise was answered.
///
/// A file of its own beside `WeekState.swift`, on `WeekEditorDayCommands.swift`'s shape and its
/// reason — the state is the screen's read, and this is a write that happens to re-run it.
extension WeekState {
    /// Rebuilds each day of the week from the session logged against it and advances the run
    /// (`FR-17.8.4`, `FR-17.8.6`).
    ///
    /// **Per answer, not per session** (`FR-17.8.6`). An exercise the lifter performed contributes
    /// what was lifted — warmups and incomplete sets left out, so `FR-16.8.5`'s "no automatic
    /// progression" is a property of where the numbers come from rather than a rule applied to them
    /// afterwards — and an exercise they *skipped* contributes the plan the day was started with
    /// (``SessionAsRoutine``). A skipped lift is not a lift dropped from the plan.
    ///
    /// **A day with no session at all keeps the routine it already has.** Nothing was said about
    /// it, so there is nothing to copy; the alternative — a routine built from a session that
    /// logged nothing — is an empty plan replacing a real one, and next week's Monday would
    /// prescribe nothing.
    ///
    /// **The routine each day replaces is archived, and only if no day still names it**
    /// (`FR-15.2.5`'s soft delete, so the previous week is recoverable). Two days may name one
    /// routine and only one of them may have been trained, in which case that routine is still in
    /// force for the other and archiving it would empty a day nobody touched.
    ///
    /// **The new routine keeps the old one's name**, read through the archive if need be: a day's
    /// name is what the lifter reads on Train, and renaming it every week would make the same day
    /// unrecognisable.
    ///
    /// **The run is advanced last, and a failure anywhere takes the minted routines back out.**
    /// The week moving is what makes the week over, so a partial rebuild that also advanced would
    /// leave the lifter in week `N+1` with some of week `N`'s days.
    ///
    /// - Parameter openSession: The workout in progress, or `nil` — passed straight through to
    ///   ``load(openSession:)`` for the re-read, on that method's own rule.
    public func startNextWeek(openSession: WorkoutSession?) async {
        do {
            try await rebuildWeek()
        } catch {
            // The read first, then the claim: a rollback may have left days re-pointed, and a card
            // still drawing the pre-rebuild week would contradict the store. `load(openSession:)`
            // retires `nextWeekFailed`, so the failure is set after it rather than before.
            await load(openSession: openSession)
            nextWeekFailed = true
            return
        }
        await load(openSession: openSession)
    }

    /// One pass of ``startNextWeek(openSession:)``. See it for every decision here.
    ///
    /// - Throws: Whatever the repositories throw, after the rollback.
    private func rebuildWeek() async throws {
        guard let run = try await programs.currentRun() else { return }
        let days = try await programs.days(forProgramID: run.programID, includingDeleted: false)
        let plans = try await weekPlans(forRunID: run.id, week: run.weekNumber)
        let writer = SessionAsRoutineWriter(repository: routines)

        var minted: [UUID] = []
        var attached: Set<UUID> = []
        do {
            var rebuilt: [(day: ProgramDay, routineID: UUID)] = []
            for day in days {
                guard let plan = plans[day.order], plan.prescribesSomething,
                    let name = try await routines.routine(id: day.routineID, includingDeleted: true)?
                        .name
                else { continue }
                let routineID = try await writer.write(plan, named: name)
                minted.append(routineID)
                rebuilt.append((day, routineID))
            }
            for (day, routineID) in rebuilt {
                try await programs.save(day.pointedAt(routineID: routineID))
                attached.insert(routineID)
            }
            try await archive(replacedBy: rebuilt, among: days)
            try await programs.save(run.advancedToNextWeek())
        } catch {
            // Only what nothing points at. A routine a day was already re-pointed to is in force
            // for that day, and deleting it would empty the day instead of undoing it.
            for routineID in minted where !attached.contains(routineID) {
                try? await routines.deleteRoutine(id: routineID)
            }
            throw error
        }
    }

    /// Archives each replaced routine that no day of the program still names.
    ///
    /// - Parameters:
    ///   - rebuilt: The days that were re-pointed, with their new routine.
    ///   - days: The program's days as they were before.
    /// - Throws: Nothing — a routine already archived is not an error here: the read that follows
    ///   sweeps its row off the screen, which is the answer to what happened to it.
    private func archive(
        replacedBy rebuilt: [(day: ProgramDay, routineID: UUID)], among days: [ProgramDay]
    ) async throws {
        let moved = Dictionary(uniqueKeysWithValues: rebuilt.map { ($0.day.id, $0.routineID) })
        let stillNamed = Set(days.map { moved[$0.id] ?? $0.routineID })
        for retired in Set(rebuilt.map(\.day.routineID)).subtracting(stillNamed) {
            try? await routines.deleteRoutine(id: retired)
        }
    }

    /// Each day of the week read back as the routine it would prescribe.
    ///
    /// **The run-and-week query** (`TR-17.5`), which is the same read the week's own cards are
    /// drawn from: the week a session belongs to is its own column (`FR-16.8.3`), and asking the
    /// store for a date range and filtering afterwards asked the wrong question of a bigger answer.
    ///
    /// **Finished sessions only, and the latest one where a day carries two.** A workout still in
    /// progress is not what the week did, and a day trained twice contributes the later attempt.
    ///
    /// **Ordered here rather than taken from the repository's own order**, which breaks its ties on
    /// a minted identifier: two attempts at one day of the week commonly share a date, and "the
    /// later one" would then be whichever `UUID` sorted higher. `startedAt` is what actually
    /// separates them.
    ///
    /// **Every entry arrives with the targets it was planned against**, because the copy is per
    /// answer and a skipped exercise's answer *is* its plan — see ``SessionAsRoutine``.
    ///
    /// - Parameters:
    ///   - runID: The run whose sessions to read.
    ///   - week: The week those sessions were started under (`FR-16.8.3`).
    /// - Returns: The plan for each ``RepositoryInterface/ProgramDay/order`` that has one.
    /// - Throws: Whatever the workout repository throws.
    private func weekPlans(forRunID runID: UUID, week: Int) async throws -> [Int: SessionAsRoutine] {
        let sessions =
            try await workouts
            .sessions(forProgramRunID: runID, week: week, includingDeleted: false)
            .filter { $0.endedAt != nil }
            .sorted { ($0.startedAt ?? $0.date) > ($1.startedAt ?? $1.date) }
        var plans: [Int: SessionAsRoutine] = [:]
        for session in sessions {
            guard let index = session.dayIndex, plans[index] == nil else { continue }
            var exercises: [SessionExercise] = []
            for entry in try await workouts.entries(forSessionID: session.id, includingDeleted: false) {
                exercises.append(
                    SessionExercise(
                        entry: entry,
                        exercise: nil,
                        sets: try await workouts.sets(forEntryID: entry.id, includingDeleted: false),
                        planned: try await workouts.plannedTargets(
                            forEntryID: entry.id, includingDeleted: false)))
            }
            plans[index] = SessionAsRoutine(exercises)
        }
        return plans
    }
}

extension SessionAsRoutine {
    /// Whether this plan prescribes anything at all.
    ///
    /// **A slot with no targets does not count**, which is what tells a day nobody answered from a
    /// day that was trained or skipped: `SessionAsRoutine` keeps every entry the workout had, so a
    /// session that was opened and finished with nothing said about it still has slots — and
    /// rebuilding a day from it would prescribe a list of exercises with no work in it.
    var prescribesSomething: Bool { slots.contains { !$0.groups.isEmpty } }
}

extension ProgramDay {
    /// This day pointing at another routine, every other column untouched.
    ///
    /// Rebuilt rather than mutated, the record being a value with `let` properties; the three
    /// timestamps are carried across because the write path is an upsert that stamps `updatedAt`
    /// itself.
    ///
    /// - Parameter routineID: The routine to train on this day from now on.
    /// - Returns: The record to store.
    func pointedAt(routineID: UUID) -> ProgramDay {
        ProgramDay(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            programID: programID,
            routineID: routineID,
            order: order)
    }
}
