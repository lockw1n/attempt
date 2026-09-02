import Foundation
import RepositoryInterface

/// Why a duplicate, rename or archive changed nothing (`FR-15.2.5`).
///
/// **Two answers rather than a `Bool`, for ``RoutineStartOutcome``'s reason**: an empty name names
/// something the lifter can fix in the field they just emptied, while a refused write names nothing
/// they did and asks only for another attempt. Collapsed into one the second would wear the first's
/// advice, which is the defect T-15.03's review found on the other command.
public enum RoutineManagementFailure: Sendable, Equatable {
    /// Nothing was renamed: the field held no name.
    case nameRequired

    /// Nothing was written: the store refused.
    ///
    /// The diagnostic stays with the store that produced it (`G-3.4`) — what this screen needs is
    /// which sentence to draw.
    case writeFailed
}

/// `FR-15.2.5`'s three commands over the library the list is showing.
///
/// **A file of its own beside ``RoutineListState``**, which is `ActiveSessionRoutineStart`'s shape
/// and its reason: the state is the screen's read, and these are writes that happen to re-run it.
///
/// **Each one re-reads on success and only on success.** A read clears both this screen's failures
/// (see ``RoutineListState/managementFailure``), so reporting a refusal and then reloading would
/// retire the sentence in the same turn it was written.
extension RoutineListState {
    /// Copies a routine, its slots and their targets into a new routine (`FR-15.2.5`).
    ///
    /// **New identifiers at all three levels**, which is what makes the copy editable independently
    /// of the original: sharing a slot id would make one editor's save the other's.
    ///
    /// **Written routine → slot → group**, the order the repository imposes rather than a
    /// preference — `save(_:)` refuses a dangling reference per key. `RoutineEditorState.save()` is
    /// the same walk.
    ///
    /// **Positions are renumbered from zero** rather than carried across, on
    /// `ActiveSessionStore.start(on:fromRoutineID:in:)`'s rule: a stored `order` is a position in a
    /// list a soft delete may have left gaps in.
    ///
    /// A routine that is no longer there is not a failure — the read that follows sweeps its row off
    /// the screen, which is the answer to what happened to it.
    ///
    /// - Parameter routineID: The routine to copy.
    public func duplicate(_ routineID: UUID) async {
        do {
            guard let original = try await repository.routine(id: routineID, includingDeleted: false)
            else {
                await load()
                return
            }
            try await write(copyOf: original)
        } catch {
            managementFailure = .writeFailed
            return
        }
        await load()
    }

    /// Retitles a routine, leaving everything under it alone (`FR-15.2.5`).
    ///
    /// **Trimmed, and an empty name is refused** — the editor's own rule (`RoutineEditorState`'s
    /// `trimmedName`), applied at the second place a name can now be typed. A rename that stored
    /// whitespace would author exactly the row the list draws **Unnamed routine** for.
    ///
    /// - Parameters:
    ///   - routineID: The routine to retitle.
    ///   - name: What the lifter typed.
    public func rename(_ routineID: UUID, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            managementFailure = .nameRequired
            return
        }
        do {
            guard let original = try await repository.routine(id: routineID, includingDeleted: false)
            else {
                await load()
                return
            }
            // The record is rebuilt whole because `Routine` is immutable, and every column but
            // the name is the original's: this screen edits one field and must not decide the
            // others. `createdAt` and `deletedAt` are pinned by the upsert regardless, and
            // `updatedAt` is restamped by it — passing the original's values is the honest no-op,
            // not a rule this layer enforces.
            try await repository.save(
                Routine(
                    id: original.id,
                    createdAt: original.createdAt,
                    updatedAt: original.updatedAt,
                    deletedAt: original.deletedAt,
                    name: trimmed))
        } catch {
            managementFailure = .writeFailed
            return
        }
        await load()
    }

    /// Takes a routine out of the library (`FR-15.2.5`).
    ///
    /// **Archive is the repository's soft delete, cascading to the slots and their targets**
    /// (`G-1.3`) — the posture `FR-1.1.5`'s exercise archive takes, one layer down. What it does
    /// *not* touch is the workouts already started from it: those copied their targets when they
    /// started (`TR-15.3`), so a session's plan outlives the routine it came from.
    ///
    /// **There is no way back from here in this slice, and that is a decision rather than an
    /// omission.** `FR-15.2.5` names no unarchive, and offering one would need either a repository
    /// that can un-cascade a delete — the slots and groups go with the routine, and `save(_:)`
    /// restores only the row it is given — or an `isArchived` column of the kind the exercise
    /// catalogue has. The screen asks for confirmation instead.
    ///
    /// A routine that is no longer there is not a failure, ``duplicate(_:)``'s reading: the read
    /// that follows sweeps its row off the screen, which is the answer to what happened to it.
    /// Asking again for a routine already archived is the one way the store says `recordNotFound`
    /// here, and telling the lifter their archive could not be saved would ask them to retry
    /// something that has already happened.
    ///
    /// - Parameter routineID: The routine to archive.
    public func archive(_ routineID: UUID) async {
        do {
            try await repository.deleteRoutine(id: routineID)
        } catch RepositoryError.recordNotFound {
            await load()
            return
        } catch {
            managementFailure = .writeFailed
            return
        }
        await load()
    }

    /// Writes the copy: the routine, then each slot, then each slot's targets.
    ///
    /// **A write that fails part-way takes the copy back out**, which is what makes
    /// ``RoutineManagementFailure/writeFailed`` mean what it says. The routine row lands first by
    /// necessity, so a store that refuses a slot leaves a routine in the library the lifter did not
    /// ask for — and a retry cannot finish it, every attempt minting fresh identifiers rather than
    /// completing the last one. That is the difference from `RoutineEditorState.save()`, whose
    /// partial write is finishable because it rewrites the same rows.
    ///
    /// - Parameter original: The routine being copied.
    private func write(copyOf original: Routine) async throws {
        let slots = try await repository.exercises(
            forRoutineID: original.id, includingDeleted: false)
        var targets: [[RoutineTargetGroup]] = []
        for slot in slots {
            targets.append(
                try await repository.targetGroups(
                    forRoutineExerciseID: slot.id, includingDeleted: false))
        }

        let now = Date.now
        let copyID = UUID()
        try await repository.save(
            Routine(
                id: copyID,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                name: String(localized: RoutinesStrings.listDuplicateName(original.name))))
        do {
            try await write(slots, targets, under: copyID)
        } catch {
            // The cascade takes the slots and groups that did land with it (`G-1.3`). A cleanup
            // that fails too leaves what the caller is about to report anyway.
            try? await repository.deleteRoutine(id: copyID)
            throw error
        }
    }

    /// Writes a copy's slots and their targets under the routine row that already landed.
    ///
    /// - Parameters:
    ///   - slots: The original's slots, in order.
    ///   - targets: Each slot's targets, in the same order.
    ///   - copyID: The routine they hang off.
    private func write(
        _ slots: [RoutineExercise], _ targets: [[RoutineTargetGroup]], under copyID: UUID
    ) async throws {
        let now = Date.now
        for (position, slot) in slots.enumerated() {
            let slotID = UUID()
            try await repository.save(
                RoutineExercise(
                    id: slotID,
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil,
                    routineID: copyID,
                    exerciseID: slot.exerciseID,
                    order: position))
            for (index, group) in targets[position].enumerated() {
                try await repository.save(
                    RoutineTargetGroup(
                        id: UUID(),
                        createdAt: now,
                        updatedAt: now,
                        deletedAt: nil,
                        routineExerciseID: slotID,
                        order: index,
                        // The optional is copied AS an optional: a blank target carried across as
                        // zero would turn "decide it in the session" into an empty bar, which is
                        // the distinction `FR-15.2.2` exists for.
                        targetWeight: group.targetWeight,
                        targetReps: group.targetReps,
                        targetSets: group.targetSets))
            }
        }
    }
}
