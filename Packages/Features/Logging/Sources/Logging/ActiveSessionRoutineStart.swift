import Foundation
import PowerliftingCore
import RepositoryInterface

/// `FR-15.2.3`'s third way into a workout: a fresh session carrying a routine's exercises and the
/// targets it prescribed for them.
///
/// A file of its own beside ``ActiveSessionRepeat``, whose shape it follows — the same store, the
/// same reason (`ActiveSessionStore` had reached SwiftLint's length ceiling long before this).
extension ActiveSessionStore {
    /// Starts a workout on `day` carrying the exercises and targets `routineID` prescribes
    /// (`FR-15.2.3`, `TR-15.3`).
    ///
    /// **The targets are copied, not referenced, and that is `TR-15.3`.** Each group's
    /// ``RepositoryInterface/RoutineTargetGroup/prescription`` is resolved here and the resulting
    /// weight is written onto the session's own entry, so editing the routine tomorrow rewrites the
    /// plan for the next workout and leaves this one saying what it was told today.
    ///
    /// **This is where `PrescriptionResolver` reaches production** (`TR-15.4`). Today every
    /// prescription that arrives is ``PowerliftingCore/Prescription/fixedWeight(_:)``, for which
    /// resolution is close to an identity — see ``resolvedTarget(for:using:in:)`` for the one thing
    /// it nevertheless decides — but the call is the path Phase 2's percentage prescriptions extend
    /// rather than replace.
    ///
    /// **It refuses while a workout is in progress**, which is ``start(on:)``'s invariant rather
    /// than a new one. A caller that has not looked yet should ``resume()`` first.
    ///
    /// **The copy is best-effort and the workout is kept either way**, on
    /// ``start(on:repeating:)``'s argument: a plan that could not be written leaves the lifter in a
    /// workout they can log into, and discarding it to report the failure would throw away a
    /// session row `NFR-1.8` has already persisted.
    ///
    /// - Parameters:
    ///   - day: The training day the new workout belongs to.
    ///   - routineID: The routine to take the exercises and targets from.
    ///   - routines: Where that routine is read from. **A parameter rather than a sixth stored
    ///     dependency**: a routine is a plan this store neither owns nor writes, and it is read
    ///     exactly once, here.
    /// - Returns: Whether a workout is now in progress.
    @discardableResult
    public func start(
        on day: Date, fromRoutineID routineID: UUID, in routines: any RoutineRepository
    ) async -> Bool {
        await start(on: day, fromRoutineID: routineID, in: routines, stampedWith: nil)
    }

    /// ``start(on:fromRoutineID:in:)``, with the program run the workout belongs to written into
    /// the session row (`FR-16.8.2`, `FR-16.8.3`).
    ///
    /// **One method with an optional stamp rather than two starts**, because everything after the
    /// session row is written is identical: a program day *is* a routine, and the whole of what a
    /// program adds to `FR-15.2.3`'s start is three columns on the row it creates.
    ///
    /// - Parameters:
    ///   - day: The training day the new workout belongs to.
    ///   - routineID: The routine the program day names.
    ///   - routines: Where that routine is read from.
    ///   - stamp: The run, week and day index to record, or `nil`.
    /// - Returns: Whether a workout is now in progress.
    @discardableResult
    func start(
        on day: Date,
        fromRoutineID routineID: UUID,
        in routines: any RoutineRepository,
        stampedWith stamp: ProgramSessionStamp?
    ) async -> Bool {
        guard session == nil else { return false }
        await start(on: day, stampedWith: stamp)
        guard let current = session else { return false }
        do {
            try await populate(current, fromRoutineID: routineID, in: routines)
            exercisesWriteFailure = nil
        } catch {
            exercisesWriteFailure = String(describing: error)
        }
        await loadExercises()
        return true
    }

    /// Writes `routineID`'s slots onto `session` as entries, each with its targets resolved.
    ///
    /// **Ordered by the routine, renumbered from zero.** The slot's own `order` is not carried
    /// across: it is a position in a plan that may have gaps a soft delete left, and an entry's
    /// order is a position in this workout.
    ///
    /// - Parameters:
    ///   - session: The workout just started.
    ///   - routineID: The routine being copied.
    ///   - routines: Where it is read from.
    private func populate(
        _ session: WorkoutSession, fromRoutineID routineID: UUID, in routines: any RoutineRepository
    ) async throws {
        let slots = try await routines.exercises(forRoutineID: routineID, includingDeleted: false)
        let resolver = PrescriptionResolver()
        // `.unrounded` is the honest rule for this slice rather than a placeholder: every
        // prescription reachable here carries a weight somebody typed, and the resolver returns
        // those untouched whatever the rule says. It becomes a real decision when Phase 2's
        // percentages arrive, at which point it is the lifter's own `defaultRoundingRule` —
        // reading that row now, to feed a value nothing reads, would put a settings failure
        // between a routine and its workout.
        let context = PrescriptionContext(rounding: .unrounded)
        let now = Date.now
        for (position, slot) in slots.enumerated() {
            let entry = ExerciseEntry(
                id: UUID(),
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                sessionID: session.id,
                exerciseID: slot.exerciseID,
                order: position,
                notes: ""
            )
            try await repository.save(entry)
            let groups = try await routines.targetGroups(
                forRoutineExerciseID: slot.id, includingDeleted: false)
            for (index, group) in groups.enumerated() {
                try await repository.save(
                    PlannedTargetGroup(
                        id: UUID(),
                        createdAt: now,
                        updatedAt: now,
                        deletedAt: nil,
                        exerciseEntryID: entry.id,
                        order: index,
                        targetWeight: Self.resolvedTarget(for: group, using: resolver, in: context),
                        targetReps: group.targetReps,
                        targetSets: group.targetSets
                    )
                )
            }
        }
    }

    /// The weight `group` prescribes, or `nil` where it prescribes none (`TR-15.4`).
    ///
    /// **`nil` covers two different facts, and the session cannot act on either differently.** A
    /// blank target (`FR-15.2.2`) has no prescription to resolve, so the resolver is not called at
    /// all; a prescription that resolves to
    /// ``PowerliftingCore/PrescriptionResolution/unspecifiedLoad`` or refuses names no weight
    /// either. Both leave the lifter deciding the load in the session, which is the same thing to
    /// do — and in this slice only the first is reachable, ``PowerliftingCore/Prescription/fixedWeight(_:)``
    /// being the one case a routine can store and one that cannot fail. **Once a prescription that
    /// can refuse is storable, a refusal owes the lifter its reason** — `FR-2.3.5` says so — and
    /// this is where that split has to be made rather than here in a snapshot column.
    ///
    /// **An entered weight comes back untouched, `context`'s rounding rule notwithstanding**
    /// (`FR-2.3.3`). That is ``PowerliftingCore/PrescriptionResolver``'s rule — derived is rounded,
    /// entered is not — and it is why this is a resolver call rather than a read of
    /// ``RepositoryInterface/RoutineTargetGroup/targetWeight``: the path is the one Phase 2's
    /// derived prescriptions arrive on, and they *are* rounded.
    ///
    /// - Parameters:
    ///   - group: The routine's target group.
    ///   - resolver: The resolver to put its prescription through.
    ///   - context: The situation to resolve against.
    /// - Returns: The weight to snapshot, or `nil`.
    static func resolvedTarget(
        for group: RoutineTargetGroup,
        using resolver: PrescriptionResolver,
        in context: PrescriptionContext
    ) -> Weight? {
        guard let prescription = group.prescription else { return nil }
        guard case .resolved(let resolved) = resolver.resolve(prescription, in: context) else {
            return nil
        }
        return resolved.target
    }
}
