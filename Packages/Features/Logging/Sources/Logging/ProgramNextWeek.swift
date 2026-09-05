import Foundation
import RepositoryInterface

/// `FR-16.8.4`'s **Start next week**: the week's days rewritten from what was actually lifted.
///
/// A file of its own beside `ProgramNextUp.swift`, on `RoutineManagementCommands`' shape and its
/// reason — the state is the screen's read, and this is a write that happens to re-run it.
extension ProgramNextUpState {
    /// Rebuilds each day of the week from the session logged against it and advances the run
    /// (`FR-16.8.4`, `FR-16.8.5`).
    ///
    /// **Nothing here writes a load the lifter did not lift.** Every target comes from
    /// ``SessionAsRoutine``, which is the sets that were performed — warmups and incomplete sets
    /// left out — so `FR-16.8.5`'s "no automatic progression" is a property of where the numbers
    /// come from rather than a rule applied to them afterwards. The new routines are ordinary
    /// library rows: every load is editable before the week is started.
    ///
    /// **A day with no finished session keeps the routine it already has**, which is what a skipped
    /// day becomes. The alternative — a routine built from a session that logged nothing — is an
    /// empty plan replacing a real one, and next week's Monday would prescribe nothing.
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
    /// The cursor moving is what makes the week over, so a partial rebuild that also advanced would
    /// leave the lifter in week `N+1` with some of week `N`'s days.
    public func startNextWeek() async {
        do {
            try await rebuildWeek()
        } catch {
            commandFailure = .nextWeekFailed
            return
        }
        await load()
    }

    /// One pass of ``startNextWeek()``. See it for every decision here.
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
    /// - Throws: Nothing — a routine already archived is not an error here, on
    ///   `RoutineListState.archive(_:)`'s reading.
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
    /// **Finished sessions only, and the latest one where a day carries two.** A workout still in
    /// progress is not what the week did, and the repository's own order is newest first — so a day
    /// logged twice contributes the later attempt.
    ///
    /// - Parameters:
    ///   - runID: The run whose sessions to read.
    ///   - week: The week those sessions were started under (`FR-16.8.3`).
    /// - Returns: The plan for each ``RepositoryInterface/ProgramDay/order`` that has one.
    /// - Throws: Whatever the workout repository throws.
    private func weekPlans(forRunID runID: UUID, week: Int) async throws -> [Int: SessionAsRoutine] {
        let sessions =
            try await workouts
            .sessions(in: Date.distantPast...Date.distantFuture, includingDeleted: false)
            .filter { $0.programRunID == runID && $0.weekNumber == week && $0.endedAt != nil }
        var plans: [Int: SessionAsRoutine] = [:]
        for session in sessions {
            guard let index = session.dayIndex, plans[index] == nil else { continue }
            var exercises: [SessionExercise] = []
            for entry in try await workouts.entries(forSessionID: session.id, includingDeleted: false) {
                exercises.append(
                    SessionExercise(
                        entry: entry,
                        exercise: nil,
                        sets: try await workouts.sets(forEntryID: entry.id, includingDeleted: false)))
            }
            plans[index] = SessionAsRoutine(exercises)
        }
        return plans
    }
}

extension SessionAsRoutine {
    /// Whether this plan prescribes anything at all.
    ///
    /// **A slot with no targets does not count**, which is what tells a skipped day from a trained
    /// one: `SessionAsRoutine` keeps every entry the workout had, so a session that was opened and
    /// finished with nothing completed still has slots — and rebuilding a day from it would
    /// prescribe a list of exercises with no work in it.
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
