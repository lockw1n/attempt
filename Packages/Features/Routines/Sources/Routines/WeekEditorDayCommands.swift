import Foundation
import RepositoryInterface

/// `FR-17.10.4`'s day actions and the two that order the week (`FR-15.2.5`, `FR-17.10.1`).
///
/// **A file of its own beside ``WeekEditorState``**, which is `RoutineManagementCommands`' shape
/// and its reason: the state is the screen's read, and these are writes that happen to re-run it.
///
/// **A day is a routine row**, so *rename* retitles the routine and *duplicate* copies it whole —
/// three levels of records with fresh identifiers, because a copy sharing a slot id would make one
/// day's edit the other's. *Remove* takes only the `ProgramDay` out (`G-1.3`, soft): a removed
/// day's sessions keep the stamp they were started with and stay on History (`FR-17.10.4`), and the
/// routine outlives the day naming it.
extension WeekEditorState {
    /// Adds an empty day to the end of the week (`FR-17.10.1`).
    ///
    /// **It writes the routine as well as the day**, there being no routine list left to pick one
    /// from (`FR-17.10.6`): a day the lifter adds is a day they then name and fill in.
    ///
    /// **The new day's order is one past the last, not the count** — orders are positions a soft
    /// delete leaves gaps in, and reusing one a deleted day still holds would put two days in one
    /// place.
    public func addDay() async {
        do {
            let programID = try await week()
            let stored = try await programs.days(forProgramID: programID, includingDeleted: true)
            let order = (stored.map(\.order).max() ?? -1) + 1
            let now = Date.now
            let routineID = UUID()
            try await routines.save(
                Routine(
                    id: routineID,
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil,
                    name: String(localized: RoutinesStrings.dayDefaultName(order + 1))))
            let dayID = UUID()
            try await programs.save(
                ProgramDay(
                    id: dayID,
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil,
                    programID: programID,
                    routineID: routineID,
                    order: order))
            // Opened as it is added: a day nobody unfolds is a day with no way to add an exercise
            // to it, and adding one is what the lifter is here for.
            openDayID = dayID
        } catch {
            writeDidFail()
            return
        }
        await load()
    }

    /// Retitles a day (`FR-17.10.4`, `FR-15.2.5`).
    ///
    /// **Trimmed, and an empty name is refused** — the rule the week's own name takes, at the
    /// second place a name is typed. A rename that stored whitespace would author exactly the row
    /// the week card draws nameless.
    ///
    /// - Parameters:
    ///   - dayID: The day to retitle.
    ///   - name: What the lifter typed.
    public func renameDay(_ dayID: UUID, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nameWasRequired()
            return
        }
        guard let day = days.first(where: { $0.id == dayID }) else { return }
        do {
            guard
                let routine = try await routines.routine(
                    id: day.routineID, includingDeleted: false)
            else {
                await load()
                return
            }
            try await routines.save(
                Routine(
                    id: routine.id,
                    createdAt: routine.createdAt,
                    updatedAt: routine.updatedAt,
                    deletedAt: routine.deletedAt,
                    name: trimmed))
        } catch {
            writeDidFail()
            return
        }
        await load()
    }

    /// Copies a day, its exercises and their targets, and puts the copy straight after it
    /// (`FR-17.10.4`, `FR-15.2.5`).
    ///
    /// **Directly after the original rather than at the end**, which is the difference a week
    /// makes: the routine list this replaces had no order at all, and a lifter duplicating day 2 of
    /// six would otherwise have to move the copy up four times.
    ///
    /// **Positions are renumbered from zero** rather than carried across, on
    /// `SessionAsRoutineWriter`'s rule: a stored `order` is a position in a list a soft delete may
    /// have left gaps in.
    ///
    /// - Parameter dayID: The day to copy.
    public func duplicateDay(_ dayID: UUID) async {
        guard let day = days.first(where: { $0.id == dayID }) else { return }
        do {
            let programID = try await week()
            guard
                let original = try await routines.routine(
                    id: day.routineID, includingDeleted: false)
            else {
                await load()
                return
            }
            let copyID = try await writeCopy(of: original)
            let stored = try await programs.days(forProgramID: programID, includingDeleted: true)
            let now = Date.now
            let copyDayID = UUID()
            try await programs.save(
                ProgramDay(
                    id: copyDayID,
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil,
                    programID: programID,
                    routineID: copyID,
                    order: (stored.map(\.order).max() ?? -1) + 1))
            var sequence = days.map(\.id)
            sequence.insert(copyDayID, at: (sequence.firstIndex(of: dayID) ?? sequence.count - 1) + 1)
            try await write(order: sequence, inProgramID: programID)
        } catch {
            writeDidFail()
            return
        }
        await load()
    }

    /// Takes one day out of the week (`FR-17.10.4`, `G-1.3`).
    ///
    /// **The `ProgramDay` alone.** The routine survives, because the sessions started from this day
    /// copied their targets when they started (`TR-15.3`) and the stamp they carry is the run, the
    /// week and the index — none of which this touches (`FR-16.8.3`).
    ///
    /// A day that is no longer there is not a failure: the read that follows sweeps its section off
    /// the screen, which is the answer to what happened to it.
    ///
    /// - Parameter dayID: The day to remove.
    public func removeDay(_ dayID: UUID) async {
        do {
            try await programs.deleteDay(id: dayID)
        } catch RepositoryError.recordNotFound {
            await load()
            return
        } catch {
            writeDidFail()
            return
        }
        if openDayID == dayID { openDayID = nil }
        await renumber(days.map(\.id).filter { $0 != dayID })
    }

    /// Moves one day up or down the week (`FR-17.10.1`).
    ///
    /// - Parameters:
    ///   - index: Its current position in ``WeekEditorState/days``.
    ///   - offset: `-1` for earlier, `1` for later.
    public func moveDay(at index: Int, by offset: Int) async {
        let target = index + offset
        guard days.indices.contains(index), days.indices.contains(target) else { return }
        days.swapAt(index, target)
        await renumber(days.map(\.id))
    }

    /// Writes a sequence of day identifiers back as orders `0…n-1` and re-reads.
    ///
    /// **Every day is rewritten, not only the pair that moved**, because a removal renumbers the
    /// tail as well — and the orders have to stay dense for a week's cards to read as days 1…n.
    ///
    /// - Parameter sequence: The days in the order they should hold.
    private func renumber(_ sequence: [UUID]) async {
        do {
            guard let programID else { return }
            try await write(order: sequence, inProgramID: programID)
        } catch {
            writeDidFail()
            return
        }
        await load()
    }

    /// Stores `sequence` as orders `0…n-1`, skipping the days already at their position.
    ///
    /// - Parameters:
    ///   - sequence: The days in the order they should hold.
    ///   - programID: The program they belong to.
    /// - Throws: Whatever the program repository throws.
    private func write(order sequence: [UUID], inProgramID programID: UUID) async throws {
        let stored = try await programs.days(forProgramID: programID, includingDeleted: false)
        let byID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
        // Only the rows the store still holds, and in `sequence`'s order: a day removed under this
        // screen must not be counted a position, or every day after it keeps the order it had.
        for (position, day) in sequence.compactMap({ byID[$0] }).enumerated()
        where day.order != position {
            try await programs.save(day.reordered(to: position))
        }
    }

    /// Writes a copy of a routine: the row, then each slot, then each slot's targets.
    ///
    /// **Written routine → slot → group**, the order the repository imposes rather than a
    /// preference — `save(_:)` refuses a dangling reference per key.
    ///
    /// **A write that fails part-way takes the copy back out.** The routine row lands first by
    /// necessity, so a store that refuses a slot would otherwise leave a routine nothing names and
    /// nothing can reach.
    ///
    /// - Parameter original: The routine being copied.
    /// - Returns: The copy's identifier.
    /// - Throws: Whatever the routine repository throws.
    private func writeCopy(of original: Routine) async throws -> UUID {
        let slots = try await routines.exercises(
            forRoutineID: original.id, includingDeleted: false)
        var targets: [[RoutineTargetGroup]] = []
        for slot in slots {
            targets.append(
                try await routines.targetGroups(
                    forRoutineExerciseID: slot.id, includingDeleted: false))
        }
        let now = Date.now
        let copyID = UUID()
        try await routines.save(
            Routine(
                id: copyID,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                name: String(localized: RoutinesStrings.dayDuplicateName(original.name))))
        do {
            for (position, slot) in slots.enumerated() {
                let slotID = UUID()
                try await routines.save(
                    RoutineExercise(
                        id: slotID,
                        createdAt: now,
                        updatedAt: now,
                        deletedAt: nil,
                        routineID: copyID,
                        exerciseID: slot.exerciseID,
                        order: position))
                for (index, group) in targets[position].enumerated() {
                    try await routines.save(
                        RoutineTargetGroup(
                            id: UUID(),
                            createdAt: now,
                            updatedAt: now,
                            deletedAt: nil,
                            routineExerciseID: slotID,
                            order: index,
                            // The optional is copied AS an optional: a blank target carried across
                            // as zero would turn "decide it in the session" into an empty bar,
                            // which is the distinction `FR-15.2.2` exists for.
                            targetWeight: group.targetWeight,
                            targetReps: group.targetReps,
                            targetSets: group.targetSets))
                }
            }
        } catch {
            // The cascade takes the slots and groups that did land with it (`G-1.3`). A cleanup
            // that fails too leaves what the caller is about to report anyway.
            try? await routines.deleteRoutine(id: copyID)
            throw error
        }
        return copyID
    }
}

extension ProgramDay {
    /// This day at another position, every other column untouched.
    ///
    /// - Parameter order: Its new position in the week.
    /// - Returns: The record to store.
    func reordered(to order: Int) -> ProgramDay {
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
