import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData

/// One change to an exercise's training max, from a date (`TR-15.1`, `FR-1.5.1.4`, `FR-16.7.2`).
///
/// **The value's only home.** ``TrainingMaxConfigEntity`` says how a training max is arrived at;
/// this says what it *was*. Nothing stores a "current" one — the number in force is the latest row
/// here effective on or before the date being asked about, which is `G-1.4` applied to a column a
/// screen would otherwise be tempted to cache.
///
/// **``oldGrams`` is written rather than derived.** The row it replaced is a lookup with more than
/// one answer — a soft-deleted entry, a restored file, two rows sharing an effective date — where
/// `FR-1.5.1.4`'s "old value" is a fact the change itself knew. `nil` on the first entry for an
/// exercise, which is a different statement from a change from zero.
///
/// **``reason`` is free text.** `FR-16.7.2` names `coach` as the case that prompted the column, not
/// as a vocabulary to hold: a closed set would either refuse the lifter's sentence or file it under
/// *other*. So it is not a `…RawValue` column and resolves through nothing.
@Model
final class TrainingMaxHistoryEntity: StoredEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// The ``ExerciseEntity`` whose training max changed.
    var exerciseID: UUID = SchemaDefaults.unlinkedID

    /// When this value takes effect — the day it applies from, not the day it was typed.
    var effectiveFrom: Date = SchemaDefaults.effectiveFrom

    /// What the training max was before this change, in grams (`G-1.1`), or `nil` where there was
    /// none.
    var oldGrams: Int?

    /// What it becomes, in grams.
    ///
    /// Defaulted to zero, which carries no choice: a row this app did not write has no number in it,
    /// and zero is the reading a lifter notices rather than one that quietly resolves. Unvalidated
    /// here, as every weight column in this schema is.
    var newGrams: Int = 0

    /// Why it changed — `coach`, or whatever the lifter wrote. Empty where they wrote nothing, which
    /// is also the empty-string default this column carries.
    var reason: String = ""

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        effectiveFrom: Date,
        newGrams: Int,
        reason: String,
        oldGrams: Int? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.effectiveFrom = effectiveFrom
        self.newGrams = newGrams
        self.reason = reason
        self.oldGrams = oldGrams
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
