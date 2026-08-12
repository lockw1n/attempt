import Foundation
import RepositoryInterface
import SwiftData

/// `ExerciseRepository` over SwiftData (`TR-0.4.2`, `FR-1.1`, `FR-1.5.1`).
///
/// **`internal`, like the four beside it.** `PersistenceStack` hands out `any ExerciseRepository`,
/// so nothing outside this module can name a SwiftData-backed type — `TR-0.1.2` held by the
/// compiler rather than by review, the same way `internal` entities hold `TR-0.4.3`.
///
/// **The methods are not `async`, and they satisfy `async` requirements anyway.** An actor's
/// isolated synchronous method witnesses an `async` protocol requirement, because every call from
/// outside the actor is already a suspension point. Writing them `async` as well would add a hop
/// and claim an interior await that does not exist.
@ModelActor
actor SwiftDataExerciseRepository: ExerciseRepository {
    func exercises(includingDeleted: Bool) throws -> [Exercise] {
        try modelContext.rows(ExerciseEntity.self, includingDeleted: includingDeleted)
            .sortedDeterministically { ($0.name, $0.id.uuidString) }
            .map(\.record)
    }

    func exercise(id: UUID, includingDeleted: Bool) throws -> Exercise? {
        try modelContext.row(ExerciseEntity.self, id: id, includingDeleted: includingDeleted)?.record
    }

    /// Inserts or replaces the exercise, refusing a `parentExerciseID` that names no row.
    ///
    /// **The one join key on this record, and it is checked like every other.** `FR-1.1.4`'s
    /// variations hang off it and `G-2.5` declares no relationship, so nothing else would notice a
    /// parent that is not there — and afterwards a dangling parent is indistinguishable from a real
    /// one, which is the argument `danglingReference` is written on. A variation therefore has to be
    /// saved after its parent, the same ordering an entry already owes its session.
    ///
    /// **An exercise naming itself is refused too, and it has to be checked separately.** Existence
    /// alone would accept it the moment the row exists — so the identical record would be refused on
    /// the save that creates it and accepted on the next one, and `FR-1.1.4`'s variation tree would
    /// have a one-row cycle in it.
    func save(_ exercise: Exercise) throws {
        if let parentID = exercise.parentExerciseID {
            guard parentID != exercise.id else {
                throw RepositoryError.danglingReference(
                    recordID: exercise.id, referencing: parentID)
            }
            try modelContext.requireReferenced(
                ExerciseEntity.self, id: parentID, from: exercise.id)
        }
        try modelContext.upsert(exercise, as: ExerciseEntity.self)
        try modelContext.saveStamped()
    }

    /// The configuration in force, by the latest ``TrainingMaxConfigEntity/effectiveFrom`` at or
    /// before `date`.
    ///
    /// **Two entries may share an effective date**, so the pick is `effectiveFrom` first and then
    /// rule 2's own order — the same total key, with the lookup's key in front of it. Nothing here
    /// leans on a unique constraint: `FR-1.5.1.4` keeps every change, and `G-2.5` forbids the
    /// constraint that would make one of them impossible.
    func trainingMax(forExerciseID exerciseID: UUID, on date: Date) throws -> TrainingMaxEntry? {
        let inForce = try modelContext.rows(
            TrainingMaxConfigEntity.self,
            matching: #Predicate { $0.exerciseID == exerciseID && $0.effectiveFrom <= date },
            includingDeleted: false
        )
        return inForce.max {
            ($0.effectiveFrom, $0.updatedAt, $0.id.uuidString)
                < ($1.effectiveFrom, $1.updatedAt, $1.id.uuidString)
        }?.record
    }

    func trainingMaxHistory(
        forExerciseID exerciseID: UUID,
        includingDeleted: Bool
    ) throws -> [TrainingMaxEntry] {
        try modelContext.rows(
            TrainingMaxConfigEntity.self,
            matching: #Predicate { $0.exerciseID == exerciseID },
            includingDeleted: includingDeleted
        )
        .sortedDeterministically(by: { ($0.effectiveFrom, $0.id.uuidString) }, descending: true)
        .map(\.record)
    }

    func saveTrainingMax(_ entry: TrainingMaxEntry) throws {
        try modelContext.requireReferenced(
            ExerciseEntity.self, id: entry.exerciseID, from: entry.id)
        try modelContext.upsert(entry, as: TrainingMaxConfigEntity.self)
        try modelContext.saveStamped()
    }
}
