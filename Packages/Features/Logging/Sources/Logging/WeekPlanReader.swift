import Foundation
import RepositoryInterface

/// What a routine prescribes, as a week's card and a day's checklist both draw it (`FR-17.8.1`,
/// `FR-17.9.1`).
///
/// **One reader rather than a copy in each state**, and the reason is `NFR-17.4` rather than
/// tidiness: a day that assembled its plan by reading the whole week would read every started day's
/// entries to answer a question about one, which is the entry walk `T-17.10`'s review named as the
/// one that doubles silently as screens accumulate over the same state. ``DayStore`` reads the
/// plan and nothing else; ``WeekState`` reads the plan and the sessions.
///
/// **A class, for the cache.** A lift planned on three days of the same week is one catalogue read,
/// and the cache belongs to the load rather than to the type — ``reset()`` is what a re-read calls.
final class WeekPlanReader {
    /// The routines the slots belong to, and the targets they prescribe.
    private let routines: any RoutineRepository

    /// The catalogue those slots name.
    private let exercises: any ExerciseRepository

    /// The rows read so far this load.
    private var catalogue: [UUID: Exercise] = [:]

    /// Builds the reader over the two repositories a plan is assembled from.
    ///
    /// - Parameters:
    ///   - routines: The routines and their target groups.
    ///   - exercises: The catalogue the slots name.
    init(routines: any RoutineRepository, exercises: any ExerciseRepository) {
        self.routines = routines
        self.exercises = exercises
    }

    /// Forgets the catalogue rows read for the last load.
    func reset() { catalogue = [:] }

    /// What `routineID` prescribes, as the lines a card or a checklist draws.
    ///
    /// - Parameter routineID: The routine a day names.
    /// - Returns: One line per slot, in the routine's own order.
    /// - Throws: Whatever the repositories throw.
    func plan(forRoutineID routineID: UUID) async throws -> [WeekPlanLine] {
        let slots = try await routines.exercises(forRoutineID: routineID, includingDeleted: false)
        var lines: [WeekPlanLine] = []
        for slot in slots {
            let groups = try await routines.targetGroups(
                forRoutineExerciseID: slot.id, includingDeleted: false)
            lines.append(
                WeekPlanLine(
                    id: slot.id,
                    exercise: try await exercise(id: slot.exerciseID),
                    targets: groups.map(Self.target)))
        }
        return lines
    }

    /// One target group, as a card draws it.
    ///
    /// - Parameter group: The routine's prescription.
    /// - Returns: The target.
    private static func target(_ group: RoutineTargetGroup) -> WeekPlanTarget {
        WeekPlanTarget(
            id: group.id,
            weight: group.targetWeight,
            reps: group.targetReps,
            sets: group.targetSets)
    }

    /// One catalogue row, read at most once per load.
    ///
    /// **Soft-deleted rows included** (`G-1.3`): a plan naming an exercise that has been archived
    /// still draws its name, and dropping it would shorten the plan silently.
    ///
    /// - Parameter id: The exercise a slot names.
    /// - Returns: The row, or `nil` where the catalogue has none.
    /// - Throws: Whatever the catalogue read throws.
    private func exercise(id: UUID) async throws -> Exercise? {
        if let held = catalogue[id] { return held }
        let read = try await exercises.exercise(id: id, includingDeleted: true)
        if let read { catalogue[id] = read }
        return read
    }
}
