import Foundation
import PowerliftingCore
import RepositoryInterface
import SeedContent

extension SeedExercise {
    /// ``SeedExercise/movementRawValue`` as a domain value.
    ///
    /// The four below resolve through `RecordVocabulary`, which is the same table the stored mapping
    /// and `Codable` read — a fifth policy for the same question is how two of them drift. On a
    /// validated payload the fallback is unreachable: `SeedCatalogueValidator` refuses a spelling no
    /// domain type recognises, which is the only reason it can afford to be unreachable here.
    var movement: Movement {
        RecordVocabulary.resolve(movementRawValue, or: RecordVocabulary.movement)
    }

    /// ``SeedExercise/equipmentRawValue`` as a domain value.
    var equipment: Equipment {
        RecordVocabulary.resolve(equipmentRawValue, or: RecordVocabulary.equipment)
    }

    /// ``SeedExercise/lateralityRawValue`` as a domain value.
    var laterality: Laterality {
        RecordVocabulary.resolve(lateralityRawValue, or: RecordVocabulary.laterality)
    }

    /// ``SeedExercise/barTypeRawValue`` as a domain value.
    var barType: BarType {
        RecordVocabulary.resolve(barTypeRawValue, or: RecordVocabulary.barType)
    }
}

extension Exercise {
    /// A new row for a catalogue entry.
    ///
    /// The five columns the payload has no opinion on are decided here: a seeded exercise is not
    /// custom, is not archived, carries no notes, and is live. `createdAt` is honoured because the
    /// row is new; `updatedAt` is the repository's whatever this says.
    static func seeded(from entry: SeedExercise, at now: Date) -> Exercise {
        Exercise(
            id: entry.id,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            name: entry.name,
            movement: entry.movement,
            parentExerciseID: entry.parentExerciseID,
            equipment: entry.equipment,
            laterality: entry.laterality,
            barType: entry.barType,
            implementCount: entry.implements,
            isCustom: false,
            isArchived: false,
            notes: ""
        )
    }

    /// `self` with the six seed-owned columns re-supplied from `entry` and every other column kept.
    ///
    /// **The split is the whole rule, and this is its only home.** ``Exercise/name`` is kept because
    /// `FR-1.1.4` lets a user rename a built-in and a later import must not undo it; ``notes`` and
    /// ``isArchived`` are kept for the same reason, being edits the payload cannot express. The
    /// audit columns are copied so that a caller can compare this against the stored row and learn
    /// whether the import has anything to write.
    func reseeded(from entry: SeedExercise) -> Exercise {
        Exercise(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            name: name,
            movement: entry.movement,
            parentExerciseID: entry.parentExerciseID,
            equipment: entry.equipment,
            laterality: entry.laterality,
            barType: entry.barType,
            implementCount: entry.implements,
            isCustom: isCustom,
            isArchived: isArchived,
            notes: notes
        )
    }

    /// `self` hidden from the pickers, with its logged history intact (`FR-1.1.5`, `G-1.3`).
    ///
    /// Archiving rather than deleting is not a softer choice here, it is the only one: `FR-1.1.5`
    /// forbids hard-deleting an exercise with logged sets, and ``ExerciseRepository`` offers no soft
    /// delete either — one would orphan every set logged against the row.
    func archived() -> Exercise {
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
            isArchived: true,
            notes: notes
        )
    }
}
