import Foundation
import RepositoryInterface

/// Writes a ``SessionAsRoutine`` into the library as a routine, its slots and their targets
/// (`FR-15.2.6`, `FR-16.8.4`).
///
/// **One path, because there are two callers.** `FR-15.2.6`'s **Save as routine** and
/// `FR-16.8.4`'s **Start next week** both turn a finished workout into a plan, and a second copy of
/// the routine → slot → group walk is a second place for the rollback, the renumbering and
/// `FR-15.2.2`'s never-blank rule to disagree.
///
/// **Written routine → slot → group**, the order the repository imposes rather than a preference:
/// `save(_:)` refuses a dangling reference per key.
struct SessionAsRoutineWriter: Sendable {
    /// The library the routine lands in.
    let repository: any RoutineRepository

    /// Writes `plan` as a routine called `name`, and answers with its identifier.
    ///
    /// **A write that fails part-way takes the routine back out.** The routine row lands first by
    /// necessity, so a store that refuses a slot would otherwise leave an empty routine in the
    /// library — reported as a failure by the caller and visible as a plan there.
    ///
    /// - Parameters:
    ///   - plan: The workout read as a routine.
    ///   - name: Its name, already trimmed.
    /// - Returns: The new routine's identifier.
    /// - Throws: Whatever the repository throws.
    @discardableResult
    func write(_ plan: SessionAsRoutine, named name: String) async throws -> UUID {
        let now = Date.now
        let routineID = UUID()
        try await repository.save(
            Routine(id: routineID, createdAt: now, updatedAt: now, deletedAt: nil, name: name))
        do {
            try await write(plan, under: routineID, at: now)
        } catch {
            // The cascade takes whatever did land with it (`G-1.3`). A cleanup that fails too
            // leaves what the caller is about to report anyway.
            try? await repository.deleteRoutine(id: routineID)
            throw error
        }
        return routineID
    }

    /// Writes the plan's slots and their targets under the routine row that already landed.
    ///
    /// **Positions are renumbered from zero**, on `RoutineListState.duplicate(_:)`'s rule: a stored
    /// `order` is a position in a list a soft delete may have left gaps in.
    ///
    /// - Parameters:
    ///   - plan: The workout read as a routine.
    ///   - routineID: The routine they hang off.
    ///   - now: The stamp every row written here carries.
    private func write(_ plan: SessionAsRoutine, under routineID: UUID, at now: Date) async throws {
        for (position, slot) in plan.slots.enumerated() {
            let slotID = UUID()
            try await repository.save(
                RoutineExercise(
                    id: slotID,
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil,
                    routineID: routineID,
                    exerciseID: slot.exerciseID,
                    order: position))
            for (index, group) in slot.groups.enumerated() {
                try await repository.save(
                    RoutineTargetGroup(
                        id: UUID(),
                        createdAt: now,
                        updatedAt: now,
                        deletedAt: nil,
                        routineExerciseID: slotID,
                        order: index,
                        // Never blank: every target here is a load that was actually lifted, so
                        // `FR-15.2.2`'s "decide it in the session" cannot arise from this path.
                        targetWeight: group.weight,
                        targetReps: group.reps,
                        targetSets: group.sets))
            }
        }
    }
}
