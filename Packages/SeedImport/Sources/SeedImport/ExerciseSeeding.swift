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
    /// The four columns the payload has no opinion on are decided here: a seeded exercise is not
    /// custom, is not archived, carries no notes, and is live.
    /// ``Exercise/ukrainianName`` is the payload's, absent included — see ``Exercise/reseeded(from:)``
    /// for what a *later* revision may do to it.
    /// `createdAt` is honoured because the row is new; `updatedAt` is the repository's whatever
    /// this says.
    static func seeded(from entry: SeedExercise, at now: Date) -> Exercise {
        Exercise(
            id: entry.id,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            name: entry.name,
            ukrainianName: entry.ukrainianName,
            movement: entry.movement,
            parentExerciseID: entry.parentExerciseID,
            equipment: entry.equipment,
            laterality: entry.laterality,
            barType: entry.barType,
            implementCount: entry.implements,
            isCustom: false,
            isArchived: false,
            notes: "")
    }

    /// `self` with the six seed-owned columns re-supplied from `entry` and every other column kept.
    ///
    /// **The split is the whole rule, and this is its only home.** Re-supplied on every import:
    /// ``Exercise/movement``, ``Exercise/parentExerciseID``, ``Exercise/equipment``,
    /// ``Exercise/laterality``, ``Exercise/barType``, ``Exercise/implementCount``. Kept:
    /// ``Exercise/name``, because `FR-1.1.4` lets a user rename a built-in and a later import must
    /// not undo it; ``Exercise/notes`` and ``Exercise/isArchived`` for the same reason, being
    /// edits the payload cannot express; ``Exercise/isCustom``, which decides
    /// the question rather than answering to it. The audit columns are copied so that a caller can
    /// compare this against the stored row and learn whether the import has anything to write.
    ///
    /// **A kept column is kept unconditionally unless the payload can name what the seed wrote.**
    /// Nothing stored records whether a column holds a user's edit or the value the seed last put
    /// there, so on the store alone a later revision cannot tell a rename it must preserve from a
    /// name it should fix. A column recording that would answer it, and columns are cheap only
    /// before rows exist — but it is not the only answer. A column whose past values the *payload*
    /// can enumerate is one an entry can settle from outside the store, which is what
    /// ``Exercise/name`` does below. ``Exercise/notes`` and ``Exercise/isArchived`` cannot follow
    /// it: free text the catalogue never authored, and a flag it never wrote, so there is no former
    /// value for an entry to list.
    ///
    /// **``Exercise/name`` is the one kept column with a way out, and the way out is in the payload
    /// rather than in the store** (`FR-18.2.1`, `TR-18.1`). An entry lists the names it used to
    /// carry, and a stored name still equal to one of them is a name nobody has touched — so it
    /// becomes the entry's current name, and every other stored name is kept, which is `FR-1.1.4`'s
    /// rename surviving every revision. Both languages, by the same rule. Equality is exact after
    /// trimming and folds neither case nor diacritics: a lifter who retyped the name with a capital
    /// has touched it. Two devices importing the same revision each rewrite the same name to the
    /// same value, which is last-write-wins over identical bytes and costs nothing.
    ///
    /// **``Exercise/ukrainianName`` is neither, and it is the only column that is not.** It is
    /// *filled* — taken from the entry where the row holds nothing, kept where the row holds
    /// something (and corrected, above, where what it holds is a former name). Both of the other two
    /// rules break on it: re-supplied, it would undo a Ukrainian
    /// name the user typed, the way an unconditionally re-supplied ``Exercise/name`` would undo
    /// `FR-1.1.4`'s rename; kept, it would never reach a single row on an installed app, since every
    /// built-in already exists there and the catalogue's translations arrive in a later revision by
    /// definition (`FR-1.14.2`).
    ///
    /// **What that costs is the same thing every kept column costs, one step later.** A user who
    /// clears the field puts the column back to nothing, and the next import fills it again from the
    /// catalogue — because "never set" and "deliberately emptied" are the same stored value. That is
    /// the recoverable direction: it hands back the name the catalogue ships, which is what an
    /// exercise with no Ukrainian name of its own would have shown anyway.
    func reseeded(from entry: SeedExercise) -> Exercise {
        Exercise(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            name: Exercise.corrected(name, to: entry.name, ifFormerly: entry.formerNames),
            ukrainianName: correctedUkrainianName(from: entry),
            movement: entry.movement,
            parentExerciseID: entry.parentExerciseID,
            equipment: entry.equipment,
            laterality: entry.laterality,
            barType: entry.barType,
            implementCount: entry.implements,
            isCustom: isCustom,
            isArchived: isArchived,
            notes: notes)
    }

    /// `stored` replaced by `current` when it is still one of `former`, and kept otherwise.
    ///
    /// Trimmed on both sides because leading or trailing whitespace is not an edit anyone made on
    /// purpose; nothing else is normalised, for the reason ``reseeded(from:)`` gives.
    private static func corrected(
        _ stored: String,
        to current: String,
        ifFormerly former: [String]
    ) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        let isUntouched = former.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
        }
        return isUntouched ? current : stored
    }

    /// ``Exercise/ukrainianName`` after the fill and the correction, in that order of precedence.
    ///
    /// A row holding nothing is filled, as it always was. A row holding a former name is corrected —
    /// but only towards a name the entry actually carries: an entry that lists a former Ukrainian
    /// name and no current one would otherwise *clear* the column, which is a worse answer than
    /// leaving the old name standing.
    private func correctedUkrainianName(from entry: SeedExercise) -> String? {
        guard let stored = ukrainianName else { return entry.ukrainianName }
        guard let current = entry.ukrainianName else { return stored }
        return Exercise.corrected(stored, to: current, ifFormerly: entry.formerUkrainianNames)
    }

    /// `self` hidden from the pickers, with its logged history intact (`FR-1.1.5`, `G-1.3`).
    ///
    /// Archiving rather than deleting is not a softer choice here, it is the only one: `FR-1.1.5`
    /// forbids hard-deleting an exercise with logged sets, and ``ExerciseRepository`` offers no soft
    /// delete either — one would orphan every set logged against the row.
    ///
    /// **One-way, for the reason ``Exercise/reseeded(from:)`` gives.** ``Exercise/isArchived`` is a
    /// kept column, so an entry that leaves a published catalogue and returns in a later revision
    /// stays hidden for everyone who imported the revision in between. Un-archiving on return would
    /// undo a user hiding a built-in they never use, which `FR-1.1.5` gives them, and nothing stored
    /// tells the two apart.
    func archived() -> Exercise {
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
            isArchived: true,
            notes: notes)
    }
}
