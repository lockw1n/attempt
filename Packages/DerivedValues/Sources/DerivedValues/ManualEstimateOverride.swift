import Foundation
import PowerliftingCore
import RepositoryInterface

/// `FR-1.7.5`'s manual override: the one e1RM the app does not compute.
///
/// A file of its own rather than more of ``PersonalRecordRecomputer``, on
/// `PersonalRecordSourceLinks`' rule — that type had reached SwiftLint's length ceiling. It is the
/// same actor and the same isolation.
extension PersonalRecordRecomputer {
    /// The override in force for `exerciseID`, or `nil` when the estimate is the sets' to make.
    ///
    /// **It throws rather than falling back to the computed number**, which is the opposite of how
    /// `FR-1.6.2`'s links resolve. A link that cannot be resolved costs a row its navigation; a
    /// column that cannot be read costs the screen the knowledge that a number was overridden at
    /// all, and the computed value shown in its place is one the user has already replaced. An
    /// estimate nobody can vouch for is `FR-1.13.1`'s error state, not a number.
    ///
    /// - Parameter exerciseID: The exercise.
    /// - Returns: The user's number, or `nil` — including for an exercise no row carries.
    /// - Throws: Whatever the repository throws reading the row.
    func manualEstimate(forExerciseID exerciseID: UUID) async throws -> Weight? {
        try await exercises.exercise(id: exerciseID, includingDeleted: false)?.manualE1RM
    }

    /// Sets the override, or clears it and returns the exercise to the computed estimate
    /// (`FR-1.7.5`).
    ///
    /// **Both directions are this one call, which is what makes the way back one tap.** `nil` is
    /// not a special case here: it is the ordinary value of the column for every exercise that has
    /// never been overridden, so reverting leaves a row indistinguishable from one nobody ever
    /// touched.
    ///
    /// **A value already in force writes nothing and announces nothing**, on
    /// ``formulaDidChange(to:)``'s rule and for a second reason: assigning a `@Model` property
    /// marks the row changed whatever the value was, so an unconditional save would restamp
    /// `updatedAt` — `G-2.4`'s conflict key — on a row that did not move.
    ///
    /// **The announcement is ``RecordChange/exercise(_:)``, not ``RecordChange/everyExercise``.**
    /// One exercise's e1RM moved; nothing else in the app has become stale, and no rep max has
    /// moved at all (an override is not a record — `FR-1.6.1` reads logged sets).
    ///
    /// That last part makes this announcement *wider than the change*: a subscriber drawing this
    /// exercise's rep maxes re-reads a cache that cannot have moved, and re-resolves its links.
    /// Accepted rather than narrowed with a third `RecordChange` case, because the walk is paid
    /// once per deliberate command from the user — not on the logging path `NFR-1.6` budgets — and
    /// a case every exhaustive switch in the app would have to answer costs more than it saves.
    ///
    /// - Parameters:
    ///   - weight: The number the user entered, or `nil` to revert to the computed estimate.
    ///   - exerciseID: The exercise it belongs to.
    /// - Throws: ``RepositoryInterface/RepositoryError/recordNotFound(id:)`` if no such exercise, or
    ///   whatever the repository throws reading or writing the row.
    public func setManualEstimate(_ weight: Weight?, forExerciseID exerciseID: UUID) async throws {
        guard let exercise = try await exercises.exercise(id: exerciseID, includingDeleted: false)
        else {
            throw RepositoryError.recordNotFound(id: exerciseID)
        }
        guard exercise.manualE1RM != weight else { return }
        try await exercises.save(exercise.overridingE1RM(with: weight))
        publish(.exercise(exerciseID))
    }
}

extension Exercise {
    /// `self` with `weight` as its manual estimate and every other column untouched.
    ///
    /// Here rather than beside `reseeded(from:)`: a record has no mutators, and each module that
    /// needs one writes the copy it needs where the rule for it lives (`TR-0.4.3`).
    ///
    /// - Parameter weight: The override, or `nil` to clear it.
    /// - Returns: The record to save.
    func overridingE1RM(with weight: Weight?) -> Exercise {
        Exercise(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            name: name,
            ukrainianName: ukrainianName,
            movement: movement,
            parentExerciseID: parentExerciseID,
            equipment: equipment,
            laterality: laterality,
            barType: barType,
            implementCount: implementCount,
            isCustom: isCustom,
            isArchived: isArchived,
            notes: notes,
            manualE1RM: weight)
    }
}
