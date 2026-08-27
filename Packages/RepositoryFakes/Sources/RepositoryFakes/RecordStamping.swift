import Foundation
import PowerliftingCore
import RepositoryInterface

/// A record that can be rewritten with different audit columns.
///
/// The fakes' counterpart of `Persistence`'s `update(from:)` and `init(record:)`, and it exists for
/// the same reason: rule 7 of the `RepositoryInterface` header says a repository ignores a record's
/// `updatedAt` and `deletedAt` and honours its `createdAt` only when the row is new, and a store of
/// immutable records cannot obey that without a way to put the four columns back.
///
/// **One implementation per record type, and no shortcut.** A record's properties are `let`, so
/// each conformance restates the whole memberwise initialiser — eight of them, mechanical and
/// verbose, and the alternative is a mutable mirror of every record shape, which is a second place
/// for a column to go missing. `RecordStampingTests` proves each one changes nothing but the four.
protocol AuditStamped: StoredRecord {
    /// `self` with the four audit columns replaced and every other column untouched.
    func stamped(createdAt: Date, updatedAt: Date, deletedAt: Date?) -> Self
}

extension Exercise: AuditStamped {
    func stamped(createdAt: Date, updatedAt: Date, deletedAt: Date?) -> Exercise {
        Exercise(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            name: name,
            movement: movement,
            parentExerciseID: parentExerciseID,
            equipment: equipment,
            laterality: laterality,
            barType: barType,
            implementCount: implementCount,
            isCustom: isCustom,
            isArchived: isArchived,
            notes: notes,
            manualE1RM: manualE1RM)
    }
}

extension TrainingMaxEntry: AuditStamped {
    func stamped(createdAt: Date, updatedAt: Date, deletedAt: Date?) -> TrainingMaxEntry {
        TrainingMaxEntry(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            exerciseID: exerciseID,
            source: source,
            sourceRepCount: sourceRepCount,
            manualWeight: manualWeight,
            percentage: percentage,
            roundingIncrement: roundingIncrement,
            roundingStrategy: roundingStrategy,
            progressionIncrement: progressionIncrement,
            effectiveFrom: effectiveFrom
        )
    }
}

extension WorkoutSession: AuditStamped {
    func stamped(createdAt: Date, updatedAt: Date, deletedAt: Date?) -> WorkoutSession {
        WorkoutSession(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            date: date,
            startedAt: startedAt,
            endedAt: endedAt,
            notes: notes,
            bodyweight: bodyweight,
            programRunID: programRunID,
            scheduledWorkoutID: scheduledWorkoutID
        )
    }
}

extension ExerciseEntry: AuditStamped {
    func stamped(createdAt: Date, updatedAt: Date, deletedAt: Date?) -> ExerciseEntry {
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
}

extension SetEntry: AuditStamped {
    func stamped(createdAt: Date, updatedAt: Date, deletedAt: Date?) -> SetEntry {
        SetEntry(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            entryID: entryID,
            order: order,
            weight: weight,
            reps: reps,
            rpe: rpe,
            rir: rir,
            isWarmup: isWarmup,
            isCompleted: isCompleted,
            targetWeight: targetWeight,
            targetReps: targetReps,
            modifiers: modifiers,
            notes: notes,
            completedAt: completedAt
        )
    }

    /// `self` with ``SetEntry/modifiers`` deduplicated and sorted by spelling.
    ///
    /// **The storage contract of that column, and the one column a fake gets wrong by keeping what
    /// it was handed.** `SetEntryEntity.modifiers` is `private(set)` and only
    /// `replaceInventory`-style writers reach it, so the store canonicalises on the way in; a
    /// caller that logs `[.paused, .belt, .paused]` reads back `[belt, paused]` from the real
    /// repository whatever it wrote. Applied by the save rather than by ``stamped(createdAt:updatedAt:deletedAt:)``
    /// because it is a column rule and not an audit one.
    func canonicalisingModifiers() -> SetEntry {
        SetEntry(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            entryID: entryID,
            order: order,
            weight: weight,
            reps: reps,
            rpe: rpe,
            rir: rir,
            isWarmup: isWarmup,
            isCompleted: isCompleted,
            targetWeight: targetWeight,
            targetReps: targetReps,
            modifiers: Set(modifiers.map(\.rawValue)).sorted().map(SetModifier.init(rawValue:)),
            notes: notes,
            completedAt: completedAt
        )
    }
}

extension BodyweightEntry: AuditStamped {
    func stamped(createdAt: Date, updatedAt: Date, deletedAt: Date?) -> BodyweightEntry {
        BodyweightEntry(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            date: date,
            weight: weight,
            source: source
        )
    }
}

extension EquipmentProfile: AuditStamped {
    func stamped(createdAt: Date, updatedAt: Date, deletedAt: Date?) -> EquipmentProfile {
        EquipmentProfile(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            name: name,
            barWeight: barWeight,
            collarWeight: collarWeight,
            plates: plates,
            platePairCounts: platePairCounts,
            isDefault: isDefault
        )
    }

    /// `self` with ``EquipmentProfile/isDefault`` forced to `flag`.
    ///
    /// "Exactly one default" is a fact about the *set* of rows, so no save may carry it —
    /// `EquipmentProfileEntity.isDefault` is written by `makeDefault(profileID:)` alone, and the
    /// mapping's `update(from:)` declines it for that reason. This is how the fake declines it too.
    func claiming(isDefault flag: Bool) -> EquipmentProfile {
        EquipmentProfile(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            name: name,
            barWeight: barWeight,
            collarWeight: collarWeight,
            plates: plates,
            platePairCounts: platePairCounts,
            isDefault: flag
        )
    }
}

extension UserSettings: AuditStamped {
    func stamped(createdAt: Date, updatedAt: Date, deletedAt: Date?) -> UserSettings {
        UserSettings(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            userID: userID,
            displayUnit: displayUnit,
            e1RMFormula: e1RMFormula,
            theme: theme,
            defaultRoundingIncrement: defaultRoundingIncrement,
            defaultRoundingStrategy: defaultRoundingStrategy,
            dashboardExerciseIDs: dashboardExerciseIDs
        )
    }

    /// `self`'s preferences written onto `row`'s identity — the settings row's own update rule.
    ///
    /// **Neither `id` nor `userID` moves.** The mapping's `update(from:)` writes neither, so a
    /// caller saving a record it assembled from defaults rather than from ``settings()`` edits the
    /// preferences of the row that is already there rather than replacing its identity (`TR-1.10`).
    func preferencesWritten(onto row: UserSettings) -> UserSettings {
        UserSettings(
            id: row.id,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            deletedAt: row.deletedAt,
            userID: row.userID,
            displayUnit: displayUnit,
            e1RMFormula: e1RMFormula,
            theme: theme,
            defaultRoundingIncrement: defaultRoundingIncrement,
            defaultRoundingStrategy: defaultRoundingStrategy,
            dashboardExerciseIDs: dashboardExerciseIDs
        )
    }
}

extension PersonalRecordCache: AuditStamped {
    func stamped(createdAt: Date, updatedAt: Date, deletedAt: Date?) -> PersonalRecordCache {
        PersonalRecordCache(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            exerciseID: exerciseID,
            repCount: repCount,
            weight: weight,
            sourceSetID: sourceSetID,
            achievedAt: achievedAt,
            computationVersion: computationVersion
        )
    }
}
