import Foundation
import RepositoryInterface

/// A day's exercises and their targets, written straight through (`FR-17.10.1`, `FR-17.10.5`).
///
/// **Where the write-through rule actually lives.** ``WeekEditorState`` states it; this is the file
/// that has to keep it honest across three number fields whose intermediate states cannot be
/// stored. A slot is written the moment it is chosen — an exercise in a day is a fact with no
/// intermediate state — and a target group is written the moment it *resolves*, which is the
/// earliest point at which there is a prescription to store.
///
/// **Every edit here lands on the plan and on nothing else** (`FR-17.10.5`, `Q-17.4`). A day
/// already started this week keeps the `PlannedTargetGroup` rows its session copied when it
/// started (`TR-15.3`), so the checklist and the week card can disagree for that day; it is drawn,
/// not prevented.
extension WeekEditorState {
    // MARK: - Exercises

    /// Adds an exercise to the day that is open (`FR-17.10.1`).
    ///
    /// **The open day is the target**, and not a second property: **Add exercise** is drawn inside
    /// the open day's section and is the only way here, so the day the chooser adds to is the day
    /// the chooser was opened from, by construction. The screen behind the chooser cannot change it
    /// while the chooser is up.
    ///
    /// **It reads the catalogue for the name**, which is the one read this command makes: the
    /// chooser that calls it is another module's screen and hands over an identifier, not a record.
    /// A row that cannot be read is added anyway, drawn nameless — refusing it would lose the
    /// lifter's tap over a display string.
    ///
    /// **The reading is mutated in place rather than re-read.** A day carries groups the lifter is
    /// halfway through typing and the store does not hold yet; re-reading here would throw them
    /// away on the way back from the chooser.
    ///
    /// - Parameter exerciseID: The catalogue exercise to prescribe.
    public func addExercise(id exerciseID: UUID) async {
        guard phase == .ready, let dayID = openDayID,
            let day = days.first(where: { $0.id == dayID })
        else { return }
        let exercise = try? await catalogue.exercise(id: exerciseID, includingDeleted: false)
        let slotID = UUID()
        do {
            let stored = try await routines.exercises(
                forRoutineID: day.routineID, includingDeleted: true)
            let now = Date.now
            try await routines.save(
                RoutineExercise(
                    id: slotID,
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil,
                    routineID: day.routineID,
                    exerciseID: exerciseID,
                    order: (stored.map(\.order).max() ?? -1) + 1))
        } catch {
            writeDidFail()
            return
        }
        // Located again: the awaits above are suspension points, and the index this started from
        // is not evidence about the array it ends on.
        guard let index = days.firstIndex(where: { $0.id == dayID }) else { return }
        days[index].slots.append(
            RoutineSlotDraft(
                id: slotID,
                exerciseID: exerciseID,
                name: exercise?.displayName(in: nameLanguage) ?? "",
                // One empty group, because a slot with none is a slot with nothing to fill in —
                // `FR-15.2.2`'s blank target is an empty weight, not an absent group. It is in no
                // table until it resolves.
                groups: [RoutineGroupDraft()]))
        writeDidLand()
    }

    /// Takes one exercise out of a day (`G-1.3`, soft — the targets cascade).
    ///
    /// - Parameters:
    ///   - slotIndex: Its position in the day.
    ///   - dayIndex: The day's position in the week.
    public func removeSlot(_ slotIndex: Int, inDayAt dayIndex: Int) async {
        guard let slot = slot(slotIndex, inDayAt: dayIndex) else { return }
        do {
            try await routines.deleteRoutineExercise(id: slot.id)
        } catch RepositoryError.recordNotFound {
            // Already gone: the row is dropped from the reading, which is the answer to what
            // happened to it.
        } catch {
            writeDidFail()
            return
        }
        guard days.indices.contains(dayIndex), days[dayIndex].slots.indices.contains(slotIndex)
        else { return }
        persistedGroupIDs.subtract(days[dayIndex].slots[slotIndex].groups.map(\.id))
        days[dayIndex].slots.remove(at: slotIndex)
        await writeSlotOrders(inDayAt: dayIndex)
    }

    /// Moves one exercise up or down a day.
    ///
    /// **Explicit commands rather than a drag**, twice over: `TR-1.12`'s `ImageRenderer` harness
    /// rasterises `List`'s `.onMove` as a placeholder, and a drag is the one reorder gesture
    /// VoiceOver and Switch Control cannot perform (`G-4.2`).
    ///
    /// - Parameters:
    ///   - slotIndex: Its position in the day.
    ///   - offset: `-1` for earlier, `1` for later.
    ///   - dayIndex: The day's position in the week.
    public func moveSlot(_ slotIndex: Int, by offset: Int, inDayAt dayIndex: Int) async {
        guard days.indices.contains(dayIndex) else { return }
        let target = slotIndex + offset
        guard days[dayIndex].slots.indices.contains(slotIndex),
            days[dayIndex].slots.indices.contains(target)
        else { return }
        days[dayIndex].slots.swapAt(slotIndex, target)
        await writeSlotOrders(inDayAt: dayIndex)
    }

    /// Writes a day's slots back at their drawn positions.
    ///
    /// - Parameter dayIndex: The day's position in the week.
    private func writeSlotOrders(inDayAt dayIndex: Int) async {
        guard days.indices.contains(dayIndex) else { return }
        let day = days[dayIndex]
        do {
            let stored = try await routines.exercises(
                forRoutineID: day.routineID, includingDeleted: false)
            let byID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
            for (position, slot) in day.slots.compactMap({ byID[$0.id] }).enumerated()
            where slot.order != position {
                try await routines.save(slot.reordered(to: position))
            }
        } catch {
            writeDidFail()
            return
        }
        writeDidLand()
    }

    // MARK: - Targets

    /// Adds an empty target group to an exercise (`FR-15.2.1`'s amendment).
    ///
    /// **Nothing is written.** An empty group prescribes nothing, and there is no reps count a
    /// store could hold that would mean "not decided yet" — see ``commitTarget(_:inSlot:inDayAt:)``.
    ///
    /// - Parameters:
    ///   - slotIndex: The exercise's position in the day.
    ///   - dayIndex: The day's position in the week.
    public func addTarget(toSlot slotIndex: Int, inDayAt dayIndex: Int) {
        guard days.indices.contains(dayIndex), days[dayIndex].slots.indices.contains(slotIndex)
        else { return }
        days[dayIndex].slots[slotIndex].groups.append(RoutineGroupDraft())
        writeDidLand()
    }

    /// Applies a keystroke to one target's fields, synchronously.
    ///
    /// **Synchronous, and separate from the write.** A `TextField`'s binding setter runs on the
    /// keystroke; a mutation deferred into a `Task` would let the field render the previous value
    /// for a turn, which is what makes a bound field jitter as it is typed into. The write is
    /// ``commitTarget(_:inSlot:inDayAt:)``, spawned by the same setter.
    ///
    /// - Parameters:
    ///   - groupIndex: The target's position in the exercise.
    ///   - slotIndex: The exercise's position in the day.
    ///   - dayIndex: The day's position in the week.
    ///   - change: What the keystroke does to the draft.
    /// - Returns: Whether the draft actually moved — a binding rewriting the same value has not
    ///   changed anything and is owed no write.
    @discardableResult
    func editTarget(
        _ groupIndex: Int,
        inSlot slotIndex: Int,
        inDayAt dayIndex: Int,
        _ change: (inout RoutineGroupDraft) -> Void
    ) -> Bool {
        guard days.indices.contains(dayIndex), days[dayIndex].slots.indices.contains(slotIndex),
            days[dayIndex].slots[slotIndex].groups.indices.contains(groupIndex)
        else { return false }
        let before = days[dayIndex].slots[slotIndex].groups[groupIndex]
        change(&days[dayIndex].slots[slotIndex].groups[groupIndex])
        guard days[dayIndex].slots[slotIndex].groups[groupIndex] != before else { return false }
        writeDidLand()
        return true
    }

    /// Stores one target group, if it is one yet (`FR-17.10.1`).
    ///
    /// **A group that does not resolve is not written, and an already-stored row is left alone.**
    /// The three fields pass through unstorable states while being typed — an emptied reps field is
    /// the ordinary one — and `RoutineTargetGroup.targetReps` is not optional, so there is no value
    /// that could stand for "the lifter is midway through". Writing a zero would prescribe doing
    /// nothing; deleting the row would lose a prescription over a keystroke. What a lifter who
    /// empties a field and leaves sees on the next read is the value the store still holds, which
    /// is the honest answer to a write-through that had nothing to write.
    ///
    /// **The draft is read here rather than carried in**, which is what makes two keystrokes'
    /// writes safe in either order: each writes whatever the field holds when it runs, so the last
    /// one to run writes the final text whichever keystroke spawned it.
    ///
    /// - Parameters:
    ///   - groupIndex: The target's position in the exercise.
    ///   - slotIndex: The exercise's position in the day.
    ///   - dayIndex: The day's position in the week.
    public func commitTarget(_ groupIndex: Int, inSlot slotIndex: Int, inDayAt dayIndex: Int) async {
        guard let slot = slot(slotIndex, inDayAt: dayIndex),
            slot.groups.indices.contains(groupIndex)
        else { return }
        let group = slot.groups[groupIndex]
        guard group.isResolvable(unit: unit, locale: locale) else { return }
        let now = Date.now
        do {
            try await routines.save(
                RoutineTargetGroup(
                    id: group.id,
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil,
                    routineExerciseID: slot.id,
                    order: groupIndex,
                    // Blank stays blank: `weight(unit:locale:)` answers `nil` to an empty field,
                    // and `isResolvable` has already refused every other way of getting one.
                    targetWeight: group.weight(unit: unit, locale: locale),
                    targetReps: group.reps(locale: locale) ?? 0,
                    targetSets: group.sets(locale: locale) ?? 0))
        } catch {
            writeDidFail()
            return
        }
        persistedGroupIDs.insert(group.id)
        writeDidLand()
    }

    /// Takes one target off an exercise.
    ///
    /// **Only a group the store actually holds is deleted.** One added and emptied inside a session
    /// was never written, and `deleteTargetGroup(id:)` throws `recordNotFound` on it — which would
    /// report a failure over a row that never existed.
    ///
    /// - Parameters:
    ///   - groupIndex: The target's position in the exercise.
    ///   - slotIndex: The exercise's position in the day.
    ///   - dayIndex: The day's position in the week.
    public func removeTarget(_ groupIndex: Int, inSlot slotIndex: Int, inDayAt dayIndex: Int) async {
        guard let slot = slot(slotIndex, inDayAt: dayIndex),
            slot.groups.indices.contains(groupIndex)
        else { return }
        let group = slot.groups[groupIndex]
        if persistedGroupIDs.contains(group.id) {
            do {
                try await routines.deleteTargetGroup(id: group.id)
            } catch RepositoryError.recordNotFound {
                // Already gone; the reading drops it either way.
            } catch {
                writeDidFail()
                return
            }
            persistedGroupIDs.remove(group.id)
        }
        guard days.indices.contains(dayIndex), days[dayIndex].slots.indices.contains(slotIndex),
            days[dayIndex].slots[slotIndex].groups.indices.contains(groupIndex)
        else { return }
        days[dayIndex].slots[slotIndex].groups.remove(at: groupIndex)
        await writeTargetOrders(inSlot: slotIndex, inDayAt: dayIndex)
    }

    /// Moves one target towards the top set or towards the backoff.
    ///
    /// - Parameters:
    ///   - groupIndex: Its position in the exercise.
    ///   - offset: `-1` for earlier, `1` for later.
    ///   - slotIndex: The exercise's position in the day.
    ///   - dayIndex: The day's position in the week.
    public func moveTarget(
        _ groupIndex: Int, by offset: Int, inSlot slotIndex: Int, inDayAt dayIndex: Int
    ) async {
        guard days.indices.contains(dayIndex), days[dayIndex].slots.indices.contains(slotIndex)
        else { return }
        let target = groupIndex + offset
        guard days[dayIndex].slots[slotIndex].groups.indices.contains(groupIndex),
            days[dayIndex].slots[slotIndex].groups.indices.contains(target)
        else { return }
        days[dayIndex].slots[slotIndex].groups.swapAt(groupIndex, target)
        await writeTargetOrders(inSlot: slotIndex, inDayAt: dayIndex)
    }

    /// Writes an exercise's stored targets back at their drawn positions.
    ///
    /// Groups the store does not hold are skipped and take no position with them, so a half-typed
    /// group sitting between two stored ones does not open a gap in the orders.
    ///
    /// - Parameters:
    ///   - slotIndex: The exercise's position in the day.
    ///   - dayIndex: The day's position in the week.
    private func writeTargetOrders(inSlot slotIndex: Int, inDayAt dayIndex: Int) async {
        guard let slot = slot(slotIndex, inDayAt: dayIndex) else { return }
        do {
            let stored = try await routines.targetGroups(
                forRoutineExerciseID: slot.id, includingDeleted: false)
            let byID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
            for (position, group) in slot.groups.compactMap({ byID[$0.id] }).enumerated()
            where group.order != position {
                try await routines.save(group.reordered(to: position))
            }
        } catch {
            writeDidFail()
            return
        }
        writeDidLand()
    }

    /// One exercise of one day, or `nil` where either index has moved out from under the caller.
    ///
    /// - Parameters:
    ///   - slotIndex: The exercise's position in the day.
    ///   - dayIndex: The day's position in the week.
    /// - Returns: The draft.
    func slot(_ slotIndex: Int, inDayAt dayIndex: Int) -> RoutineSlotDraft? {
        guard days.indices.contains(dayIndex), days[dayIndex].slots.indices.contains(slotIndex)
        else { return nil }
        return days[dayIndex].slots[slotIndex]
    }
}

extension RoutineExercise {
    /// This slot at another position, every other column untouched.
    ///
    /// - Parameter order: Its new position in the day.
    /// - Returns: The record to store.
    func reordered(to order: Int) -> RoutineExercise {
        RoutineExercise(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            routineID: routineID,
            exerciseID: exerciseID,
            order: order)
    }
}

extension RoutineTargetGroup {
    /// This target at another position, every other column untouched.
    ///
    /// - Parameter order: Its new position in the exercise.
    /// - Returns: The record to store.
    func reordered(to order: Int) -> RoutineTargetGroup {
        RoutineTargetGroup(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            routineExerciseID: routineExerciseID,
            order: order,
            targetWeight: targetWeight,
            targetReps: targetReps,
            targetSets: targetSets)
    }
}
