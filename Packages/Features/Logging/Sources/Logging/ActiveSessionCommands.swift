import Foundation
import PowerliftingCore
import RepositoryInterface

/// What the workout's commands write, and the chain they write in (`FR-1.2.2`, `FR-1.2.3`,
/// `FR-1.2.4`, `FR-1.2.5`, `FR-1.2.6`, `NFR-1.8`).
///
/// A second file rather than a longer one: ``ActiveSessionStore`` proper is the workout's lifecycle
/// and what it holds, and this is every mutation a card can issue. They share ``pendingWrite``,
/// which is why the store's repositories are internal rather than private.
extension ActiveSessionStore {
    /// Appends `exerciseID` to the workout (`FR-1.2.2`, `FR-1.2.13`).
    ///
    /// **Appended, never inserted.** `FR-1.2.13` says so outright, and the reason is the scroll
    /// position: an exercise that landed next to whichever card the user was looking at would move
    /// the list under their thumb mid-workout. The new entry's order is one past the highest in the
    /// workout rather than the count, so a list that has already been reordered — or that has a gap
    /// a soft-deleted entry left — still gets a position no other row holds.
    ///
    /// **Written through before it is held** (`NFR-1.8`), like every other mutation here, and the
    /// list is then re-read rather than appended to in memory: the entry's stored `updatedAt` is the
    /// save path's, and the sets and catalogue row it is shown with are reads of their own.
    ///
    /// - Parameter exerciseID: The catalogue row to add. A dangling one is refused by the
    ///   repository and reported as a failed write.
    public func addExercise(id exerciseID: UUID) async {
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.writeAddedExercise(id: exerciseID)
        }
        pendingWrite = write
        await write.value
    }

    /// One link in ``pendingWrite``'s chain. See ``addExercise(id:)``.
    ///
    /// **Nothing is reported when no workout is held**, and that is the composing screen's business
    /// rather than a diagnostic: the chooser is pushed above the workout, so a selection made with
    /// no workout in progress returns to a screen already saying so. See `Route.exercisePicker`.
    fileprivate func writeAddedExercise(id exerciseID: UUID) async {
        guard let current = session else { return }
        do {
            // Read for the highest position rather than measuring the held list: the chooser can be
            // reached by a restored navigation stack that never drew the workout, in which case
            // nothing has been loaded and every exercise would be added at position zero.
            let stored = try await repository.entries(forSessionID: current.id, includingDeleted: false)
            let now = Date.now
            try await repository.save(
                ExerciseEntry(
                    id: UUID(),
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil,
                    sessionID: current.id,
                    exerciseID: exerciseID,
                    order: (stored.map(\.order).max() ?? -1) + 1,
                    notes: ""
                )
            )
            exercisesWriteFailure = nil
        } catch {
            exercisesWriteFailure = String(describing: error)
        }
        await loadExercises()
    }

    /// Moves one exercise `offset` places through the workout, renumbering it (`FR-1.2.2`).
    ///
    /// **Named and relative, not two indices.** The control that calls this is a pair of buttons on
    /// a card, and a card knows which exercise it is rather than where the list will have put it by
    /// the time the tap is served. Two taps on *move down* are then two places down, because the
    /// second resolves the exercise afresh; with indices, the second tap would have carried the
    /// position the first one just vacated and undone it.
    ///
    /// **Only the rows whose position actually changed are written.** Saving all of them would
    /// restamp `updatedAt` on rows that did not move — and `updatedAt` is `G-2.4`'s conflict key, so
    /// a no-op local write outranks a real remote edit. Moving the first of six to the end is five
    /// writes, not six.
    ///
    /// **A partial write is left visible rather than rolled back.** There is no transaction across
    /// repository calls, so a failure halfway leaves some rows renumbered; the list is re-read
    /// afterwards either way, so what the user sees is what is stored, with the failure beside it.
    /// Rolling back by hand would be a second unprotected sequence of writes with the same problem.
    ///
    /// - Parameters:
    ///   - id: The exercise to move, by its entry.
    ///   - offset: How many places to move it — negative is earlier. An exercise this list does not
    ///     hold, a zero offset and a destination off either end all do nothing, which is what makes
    ///     "move up" on the first card a no-op rather than a guard on every caller.
    public func moveExercise(id: UUID, by offset: Int) async {
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.writeMovedExercise(id: id, by: offset)
        }
        pendingWrite = write
        await write.value
    }

    /// One link in ``pendingWrite``'s chain. See ``moveExercise(id:by:)``.
    fileprivate func writeMovedExercise(id: UUID, by offset: Int) async {
        guard offset != 0, let source = exercises.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard exercises.indices.contains(destination) else { return }
        var reordered = exercises
        reordered.insert(reordered.remove(at: source), at: destination)
        do {
            for (position, item) in reordered.enumerated() where item.entry.order != position {
                try await repository.save(Self.renumbered(item.entry, to: position))
            }
            exercisesWriteFailure = nil
        } catch {
            exercisesWriteFailure = String(describing: error)
        }
        await loadExercises()
    }

    /// Logs a set against one of the workout's exercises (`FR-1.2.3`).
    ///
    /// **Appended, and the order is read rather than counted**, for ``addExercise(id:)``'s reason:
    /// a soft-deleted set leaves a gap, and a position taken from the count would collide with one
    /// that is still there.
    ///
    /// **`isCompleted` is `true`, and that is `G-1.8` rather than a convenience.** The flag records
    /// whether the set was *performed*, and a set logged from this editor was — the user is typing
    /// it in because they just did it. Writing `false` would say the opposite, and it would say it
    /// to the personal-record calculator, which excludes incomplete sets: every set logged in Phase
    /// 1 would be invisible to `FR-1.6`. Marking one **failed** is
    /// ``markSet(id:inEntryID:isCompleted:)``, and it is a later edit of this column rather than a
    /// different default for it.
    ///
    /// **`isWarmup` is the caller's** (`FR-1.2.4`), and it is still decided in the open rather than
    /// defaulted: `G-1.8` forbids the record's initialiser from choosing either flag, so the value
    /// arrives from the editor's own switch, which starts on *working*. Changing it afterwards is
    /// ``markSet(id:inEntryID:isWarmup:)`` — a later edit of this column, not a second way of
    /// writing it.
    ///
    /// **`completedAt` is now.** The column exists to say the set was tracked live rather than
    /// entered after the fact, and nothing else in the app can establish that.
    ///
    /// - Parameters:
    ///   - entryID: The exercise to log against.
    ///   - values: What the set records — load, repetitions, rating, kind and note.
    public func addSet(toEntryID entryID: UUID, values: SetEntryValues) async {
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.writeAddedSet(toEntryID: entryID, values: values)
        }
        pendingWrite = write
        await write.value
    }

    /// Marks a logged set as a warmup or as working (`FR-1.2.4`, `FR-1.2.14`).
    ///
    /// **A correction, and the only one Phase 1 offers before `FR-1.2.7`'s editing lands.** A set
    /// gets its kind from the editor as it is logged; this is the case where that was wrong, or
    /// where the user decided afterwards that the third rung of the ramp was really the first
    /// working set. Both numbering sequences move as a consequence, which is `SetNumbering`'s and
    /// needs no write of its own — the number is derived, never stored (`G-1.4`).
    ///
    /// **A set already of that kind is not written**, and that is `G-2.4` rather than tidiness:
    /// assigning a `@Model` property marks the row changed whatever the value was, so the save would
    /// restamp `updatedAt` — the conflict key — and a no-op local write would outrank a real remote
    /// edit. The badge is a toggle, so this call arrives with the value already flipped and the
    /// guard fires only on a set the read found in a state the caller did not expect.
    ///
    /// **The row is re-read rather than taken from ``exercises``**, for the reason every command
    /// here re-reads: this runs at the back of ``pendingWrite``'s chain, so the held list is the one
    /// from before whatever is queued ahead of it.
    ///
    /// - Parameters:
    ///   - setID: The set to mark.
    ///   - entryID: The exercise it belongs to — what the repository reads sets by.
    ///   - isWarmup: Which kind it becomes.
    public func markSet(id setID: UUID, inEntryID entryID: UUID, isWarmup: Bool) async {
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.writeMarkedSet(id: setID, inEntryID: entryID, isWarmup: isWarmup)
        }
        pendingWrite = write
        await write.value
    }

    /// One link in ``pendingWrite``'s chain. See ``markSet(id:inEntryID:isWarmup:)``.
    ///
    /// **A set the read does not find is silently nothing**, like a set logged with no workout in
    /// progress: the row was deleted underneath the card and a diagnostic would report a failure
    /// against a set that is no longer on screen.
    ///
    /// **The list is re-read whether or not anything was written**, and the two cases that write
    /// nothing are the ones that need it most: a row the read could not find is a row still drawn
    /// on the card, and the re-read is what sweeps it off. Only the *write* is conditional — an
    /// unchanged row is not saved, and a no-op does not retire a diagnostic it says nothing about.
    fileprivate func writeMarkedSet(id setID: UUID, inEntryID entryID: UUID, isWarmup: Bool) async {
        guard session != nil else { return }
        do {
            let stored = try await repository.sets(forEntryID: entryID, includingDeleted: false)
            if let target = stored.first(where: { $0.id == setID }), target.isWarmup != isWarmup {
                try await repository.save(Self.marked(target, isWarmup: isWarmup))
                exercisesWriteFailure = nil
            }
        } catch {
            exercisesWriteFailure = String(describing: error)
        }
        await loadExercises()
    }

    /// Marks a logged set as completed or failed (`FR-1.2.5`).
    ///
    /// **What "failed" means here is self-reported and nothing resolves it.** Phase 1 prescribes
    /// nothing (`OUT-1.1`), so there is no target to fall short of: the flag says the lifter did not
    /// get all the reps they were going for, and ``RepositoryInterface/SetEntry/reps`` is what they
    /// did get. That column is the one `FR-1.6.1`'s N-rep max detection reads — never `targetReps`,
    /// which stays `nil` on every row this app writes until a prescription layer exists to fill it.
    ///
    /// **`completedAt` is left exactly as it was**, and that is the column's own contract rather
    /// than an omission: it records that the set was tracked live rather than entered afterwards,
    /// which a failed set was just as much as a successful one. Clearing it would make the two
    /// facts one, and the one it would destroy cannot be recovered.
    ///
    /// A set already in that state is not written, and the row is re-read rather than taken from
    /// ``exercises``, both for ``markSet(id:inEntryID:isWarmup:)``'s reasons.
    ///
    /// - Parameters:
    ///   - setID: The set to mark.
    ///   - entryID: The exercise it belongs to — what the repository reads sets by.
    ///   - isCompleted: Whether it was completed. `false` is `FR-1.2.5`'s failed set.
    public func markSet(id setID: UUID, inEntryID entryID: UUID, isCompleted: Bool) async {
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.writeCompletedSet(id: setID, inEntryID: entryID, isCompleted: isCompleted)
        }
        pendingWrite = write
        await write.value
    }

    /// One link in ``pendingWrite``'s chain. See ``markSet(id:inEntryID:isCompleted:)``.
    ///
    /// A set the read does not find is silently nothing, and the list is re-read whether or not
    /// anything was written, both for ``writeMarkedSet(id:inEntryID:isWarmup:)``'s reasons.
    fileprivate func writeCompletedSet(
        id setID: UUID, inEntryID entryID: UUID, isCompleted: Bool
    ) async {
        guard session != nil else { return }
        do {
            let stored = try await repository.sets(forEntryID: entryID, includingDeleted: false)
            let target = stored.first { $0.id == setID }
            if let target, target.isCompleted != isCompleted {
                try await repository.save(Self.completed(target, isCompleted: isCompleted))
                exercisesWriteFailure = nil
            }
        } catch {
            exercisesWriteFailure = String(describing: error)
        }
        await loadExercises()
    }

    /// Rewrites a logged set (`FR-1.2.7`).
    ///
    /// **The write itself is ``LoggedSetWriter``'s**, and every argument about what an edit carries
    /// across, what it refuses and why it is not the store's is there. What this adds is the three
    /// things a workout on screen needs and a past session does not: the chain, the diagnostic, and
    /// the re-read that puts the result on the card.
    ///
    /// - Parameters:
    ///   - setID: The set to rewrite.
    ///   - entryID: The exercise it belongs to — what the repository reads sets by.
    ///   - values: What it becomes.
    public func editSet(id setID: UUID, inEntryID entryID: UUID, to values: SetEntryValues) async {
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.writeEditedSet(id: setID, inEntryID: entryID, to: values)
        }
        pendingWrite = write
        await write.value
    }

    /// One link in ``pendingWrite``'s chain. See ``editSet(id:inEntryID:to:)``.
    ///
    /// The list is re-read whether or not anything was written, for
    /// ``writeMarkedSet(id:inEntryID:isWarmup:)``'s reason, and a write that changed nothing does
    /// not retire a diagnostic it says nothing about.
    fileprivate func writeEditedSet(
        id setID: UUID, inEntryID entryID: UUID, to values: SetEntryValues
    ) async {
        guard session != nil else { return }
        do {
            if try await setWriter.edit(id: setID, inEntryID: entryID, to: values) {
                exercisesWriteFailure = nil
            }
        } catch {
            exercisesWriteFailure = String(describing: error)
        }
        await loadExercises()
    }

    /// Soft-deletes a logged set (`FR-1.2.7`, `G-1.3`).
    ///
    /// The write is ``LoggedSetWriter``'s; see ``editSet(id:inEntryID:to:)`` for what this adds.
    ///
    /// - Parameters:
    ///   - setID: The set to delete.
    ///   - entryID: The exercise it belongs to.
    public func deleteSet(id setID: UUID, inEntryID entryID: UUID) async {
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.writeDeletedSet(id: setID, inEntryID: entryID)
        }
        pendingWrite = write
        await write.value
    }

    /// One link in ``pendingWrite``'s chain. See ``deleteSet(id:inEntryID:)``.
    fileprivate func writeDeletedSet(id setID: UUID, inEntryID entryID: UUID) async {
        guard session != nil else { return }
        do {
            if try await setWriter.delete(id: setID, inEntryID: entryID) {
                exercisesWriteFailure = nil
            }
        } catch {
            exercisesWriteFailure = String(describing: error)
        }
        await loadExercises()
    }

    /// One link in ``pendingWrite``'s chain. See ``addSet(toEntryID:values:)``.
    ///
    /// It shares the chain with the exercise commands rather than having one of its own: a set is
    /// written against an entry, and an entry can be moved or added by the same thumb between two
    /// taps of **Log set**.
    fileprivate func writeAddedSet(toEntryID entryID: UUID, values: SetEntryValues) async {
        guard session != nil else { return }
        do {
            let stored = try await repository.sets(forEntryID: entryID, includingDeleted: false)
            let now = Date.now
            try await repository.save(
                SetEntry(
                    id: UUID(),
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil,
                    entryID: entryID,
                    order: (stored.map(\.order).max() ?? -1) + 1,
                    weight: values.weight,
                    reps: values.reps,
                    rpe: values.rpe,
                    rir: nil,
                    isWarmup: values.isWarmup,
                    isCompleted: true,
                    targetWeight: nil,
                    targetReps: nil,
                    modifiers: [],
                    notes: values.notes,
                    completedAt: now
                )
            )
            exercisesWriteFailure = nil
        } catch {
            exercisesWriteFailure = String(describing: error)
        }
        await loadExercises()
    }

    /// `set` as the other kind, and every other field untouched.
    ///
    /// Rebuilt rather than mutated for ``renumbered(_:to:)``'s reason: the record is a value with
    /// `let` properties, and the write path stamps `updatedAt` itself.
    fileprivate static func marked(_ set: SetEntry, isWarmup: Bool) -> SetEntry {
        SetEntry(
            id: set.id,
            createdAt: set.createdAt,
            updatedAt: set.updatedAt,
            deletedAt: set.deletedAt,
            entryID: set.entryID,
            order: set.order,
            weight: set.weight,
            reps: set.reps,
            rpe: set.rpe,
            rir: set.rir,
            isWarmup: isWarmup,
            isCompleted: set.isCompleted,
            targetWeight: set.targetWeight,
            targetReps: set.targetReps,
            modifiers: set.modifiers,
            notes: set.notes,
            completedAt: set.completedAt
        )
    }

    /// `set` with the other outcome, and every other field untouched — `reps` and `completedAt`
    /// among them. See ``markSet(id:inEntryID:isCompleted:)`` for why both stay.
    ///
    /// Rebuilt rather than mutated for ``marked(_:isWarmup:)``'s reason.
    fileprivate static func completed(_ set: SetEntry, isCompleted: Bool) -> SetEntry {
        SetEntry(
            id: set.id,
            createdAt: set.createdAt,
            updatedAt: set.updatedAt,
            deletedAt: set.deletedAt,
            entryID: set.entryID,
            order: set.order,
            weight: set.weight,
            reps: set.reps,
            rpe: set.rpe,
            rir: set.rir,
            isWarmup: set.isWarmup,
            isCompleted: isCompleted,
            targetWeight: set.targetWeight,
            targetReps: set.targetReps,
            modifiers: set.modifiers,
            notes: set.notes,
            completedAt: set.completedAt
        )
    }

    /// `entry` at a new position, and every other field untouched.
    ///
    /// Rebuilt rather than mutated for ``ended(_:at:)``'s reason: the record is a value with `let`
    /// properties, and the write path stamps `updatedAt` itself.
    fileprivate static func renumbered(_ entry: ExerciseEntry, to order: Int) -> ExerciseEntry {
        ExerciseEntry(
            id: entry.id,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
            deletedAt: entry.deletedAt,
            sessionID: entry.sessionID,
            exerciseID: entry.exerciseID,
            order: order,
            notes: entry.notes
        )
    }
}
