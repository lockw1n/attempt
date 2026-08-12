import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData

// The four training entities. See `RecordMapping.swift` for the three members' contract and for why
// `update(from:)` leaves the audit columns alone.

extension ExerciseEntity {
    /// This row as a record. All four vocabulary columns resolve; none can fail.
    var record: Exercise {
        Exercise(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            name: name,
            movement: RecordVocabulary.resolve(movementRawValue, or: RecordVocabulary.movement),
            parentExerciseID: parentExerciseID,
            equipment: RecordVocabulary.resolve(equipmentRawValue, or: RecordVocabulary.equipment),
            laterality: RecordVocabulary.resolve(lateralityRawValue, or: RecordVocabulary.laterality),
            barType: RecordVocabulary.resolve(barTypeRawValue, or: RecordVocabulary.barType),
            implementCount: implementCount,
            isCustom: isCustom,
            isArchived: isArchived,
            notes: notes
        )
    }

    /// A new row carrying `record`.
    convenience init(record: Exercise) {
        self.init(
            id: record.id,
            name: record.name,
            movement: record.movement,
            equipment: record.equipment,
            laterality: record.laterality,
            barType: record.barType,
            isCustom: record.isCustom,
            implementCount: record.implementCount,
            parentExerciseID: record.parentExerciseID,
            isArchived: record.isArchived,
            notes: record.notes,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    /// Overwrites this row from `record`, preserving an unmappable stored spelling.
    func update(from record: Exercise) {
        name = record.name
        movementRawValue = preservingRawValue(
            record.movement, stored: movementRawValue, fallback: RecordVocabulary.movement)
        parentExerciseID = record.parentExerciseID
        equipmentRawValue = preservingRawValue(
            record.equipment, stored: equipmentRawValue, fallback: RecordVocabulary.equipment)
        lateralityRawValue = preservingRawValue(
            record.laterality, stored: lateralityRawValue, fallback: RecordVocabulary.laterality)
        barTypeRawValue = preservingRawValue(
            record.barType, stored: barTypeRawValue, fallback: RecordVocabulary.barType)
        implementCount = record.implementCount
        isCustom = record.isCustom
        isArchived = record.isArchived
        notes = record.notes
    }
}

extension WorkoutSessionEntity {
    /// This row as a record.
    var record: WorkoutSession {
        WorkoutSession(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            date: date,
            startedAt: startedAt,
            endedAt: endedAt,
            notes: notes,
            bodyweight: bodyweightGrams.map(Weight.init(grams:)),
            programRunID: programRunID,
            scheduledWorkoutID: scheduledWorkoutID
        )
    }

    /// A new row carrying `record`.
    convenience init(record: WorkoutSession) {
        self.init(
            id: record.id,
            date: record.date,
            startedAt: record.startedAt,
            endedAt: record.endedAt,
            notes: record.notes,
            bodyweightGrams: record.bodyweight?.grams,
            programRunID: record.programRunID,
            scheduledWorkoutID: record.scheduledWorkoutID,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    /// Overwrites this row from `record`.
    func update(from record: WorkoutSession) {
        date = record.date
        startedAt = record.startedAt
        endedAt = record.endedAt
        notes = record.notes
        bodyweightGrams = record.bodyweight?.grams
        programRunID = record.programRunID
        scheduledWorkoutID = record.scheduledWorkoutID
    }
}

extension ExerciseEntryEntity {
    /// This row as a record.
    var record: ExerciseEntry {
        ExerciseEntry(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            sessionID: sessionID,
            exerciseID: exerciseID,
            order: order,
            notes: notes
        )
    }

    /// A new row carrying `record`.
    convenience init(record: ExerciseEntry) {
        self.init(
            id: record.id,
            sessionID: record.sessionID,
            exerciseID: record.exerciseID,
            order: record.order,
            notes: record.notes,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    /// Overwrites this row from `record`.
    func update(from record: ExerciseEntry) {
        sessionID = record.sessionID
        exerciseID = record.exerciseID
        order = record.order
        notes = record.notes
    }
}

extension SetEntryEntity {
    /// This row as a record.
    ///
    /// `modifiers` is the one column that crosses without a fallback table: an unrecognised spelling
    /// is wrapped verbatim, because nothing re-supplies a modifier the user configured.
    var record: SetEntry {
        SetEntry(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            entryID: entryID,
            order: order,
            weight: Weight(grams: weightGrams),
            reps: reps,
            rpe: rpe,
            rir: rir,
            isWarmup: isWarmup,
            isCompleted: isCompleted,
            targetWeight: targetWeightGrams.map(Weight.init(grams:)),
            targetReps: targetReps,
            modifiers: modifiers.map(SetModifier.init(rawValue:)),
            notes: notes,
            completedAt: completedAt
        )
    }

    /// A new row carrying `record`.
    convenience init(record: SetEntry) {
        self.init(
            id: record.id,
            entryID: record.entryID,
            order: record.order,
            weightGrams: record.weight.grams,
            reps: record.reps,
            isWarmup: record.isWarmup,
            isCompleted: record.isCompleted,
            rpe: record.rpe,
            rir: record.rir,
            targetWeightGrams: record.targetWeight?.grams,
            targetReps: record.targetReps,
            modifiers: record.modifiers,
            notes: record.notes,
            completedAt: record.completedAt,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    /// Overwrites this row from `record`.
    ///
    /// Both sides canonicalise the modifier list and neither trusts the other to have done it: the
    /// record's initialiser sorts and deduplicates, and ``replaceModifiers(with:)`` is the column's
    /// only writer and does it again. That is one ordering authority applied twice, not two.
    func update(from record: SetEntry) {
        entryID = record.entryID
        order = record.order
        weightGrams = record.weight.grams
        reps = record.reps
        rpe = record.rpe
        rir = record.rir
        isWarmup = record.isWarmup
        isCompleted = record.isCompleted
        targetWeightGrams = record.targetWeight?.grams
        targetReps = record.targetReps
        replaceModifiers(with: record.modifiers.map(\.rawValue))
        notes = record.notes
        completedAt = record.completedAt
    }
}
