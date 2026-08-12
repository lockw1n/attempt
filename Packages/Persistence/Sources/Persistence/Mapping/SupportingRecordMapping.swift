import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData

// The five supporting entities. See `RecordMapping.swift` for the three members' contract.

extension BodyweightEntryEntity: RecordMappable {
    /// This row as a record.
    var record: BodyweightEntry {
        BodyweightEntry(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            date: date,
            weight: Weight(grams: weightGrams),
            source: RecordVocabulary.resolve(sourceRawValue, or: RecordVocabulary.bodyweightSource)
        )
    }

    /// A new row carrying `record`.
    convenience init(record: BodyweightEntry) {
        self.init(
            id: record.id,
            date: record.date,
            weightGrams: record.weight.grams,
            source: record.source,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    /// Overwrites this row from `record`, preserving an unmappable stored spelling.
    func update(from record: BodyweightEntry) {
        date = record.date
        weightGrams = record.weight.grams
        sourceRawValue = preservingRawValue(
            record.source, stored: sourceRawValue, fallback: RecordVocabulary.bodyweightSource)
    }
}

extension TrainingMaxConfigEntity: RecordMappable {
    /// This row as a record.
    ///
    /// The payload columns are carried whatever ``sourceRawValue`` says, and the percentage and
    /// rounding columns whatever the source is — reading either as evidence of participation is the
    /// mistake this type's own note refuses. `TrainingMaxEntry.configuration()` is where the pairing
    /// is checked.
    var record: TrainingMaxEntry {
        TrainingMaxEntry(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            exerciseID: exerciseID,
            source: RecordVocabulary.resolve(sourceRawValue, or: RecordVocabulary.trainingMaxSource),
            sourceRepCount: sourceRepCount,
            manualWeight: manualWeightGrams.map(Weight.init(grams:)),
            percentage: percentage,
            roundingIncrement: Weight(grams: roundingIncrementGrams),
            roundingStrategy: RecordVocabulary.resolve(
                roundingStrategyRawValue, or: RecordVocabulary.roundingStrategy),
            progressionIncrement: incrementGrams.map(Weight.init(grams:)),
            effectiveFrom: effectiveFrom
        )
    }

    /// A new row carrying `record`.
    convenience init(record: TrainingMaxEntry) {
        self.init(
            id: record.id,
            exerciseID: record.exerciseID,
            source: record.source,
            percentage: record.percentage,
            roundingIncrementGrams: record.roundingIncrement.grams,
            roundingStrategy: record.roundingStrategy,
            effectiveFrom: record.effectiveFrom,
            sourceRepCount: record.sourceRepCount,
            manualWeightGrams: record.manualWeight?.grams,
            incrementGrams: record.progressionIncrement?.grams,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    /// Overwrites this row from `record`, preserving an unmappable stored spelling.
    func update(from record: TrainingMaxEntry) {
        exerciseID = record.exerciseID
        sourceRawValue = preservingRawValue(
            record.source, stored: sourceRawValue, fallback: RecordVocabulary.trainingMaxSource)
        sourceRepCount = record.sourceRepCount
        manualWeightGrams = record.manualWeight?.grams
        percentage = record.percentage
        roundingIncrementGrams = record.roundingIncrement.grams
        roundingStrategyRawValue = preservingRawValue(
            record.roundingStrategy,
            stored: roundingStrategyRawValue,
            fallback: RecordVocabulary.roundingStrategy)
        incrementGrams = record.progressionIncrement?.grams
        effectiveFrom = record.effectiveFrom
    }
}

extension EquipmentProfileEntity: RecordMappable {
    /// This row as a record, pairing and all.
    ///
    /// The two lists cross verbatim — unsorted, unpaired and repeats intact if that is what the row
    /// holds. `EquipmentProfile.inventory()` is the only thing that refuses.
    var record: EquipmentProfile {
        EquipmentProfile(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            name: name,
            barWeight: Weight(grams: barWeightGrams),
            collarWeight: Weight(grams: collarWeightGrams),
            plates: plateGrams.map(Weight.init(grams:)),
            platePairCounts: platePairCounts,
            isDefault: isDefault
        )
    }

    /// A new row carrying `record`.
    ///
    /// Built through the raw-array initialiser rather than the `PlateInventory` one, because that
    /// parameter cannot express a profile whose lists break the domain type's invariants — and such
    /// a profile is precisely what this direction has to be able to write back.
    convenience init(record: EquipmentProfile) {
        self.init(
            id: record.id,
            name: record.name,
            barWeightGrams: record.barWeight.grams,
            collarWeightGrams: record.collarWeight.grams,
            plateGrams: record.plates.map(\.grams),
            platePairCounts: record.platePairCounts,
            isDefault: record.isDefault,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    /// Overwrites this row from `record`.
    ///
    /// **``EquipmentProfile/isDefault`` is not written, and it is not an omission** — the same
    /// treatment `UserSettingsEntity`'s `userID` gets, for the same reason. "Exactly one default" is
    /// a cross-row invariant that only `EquipmentRepository.makeDefault(profileID:)` can hold, and
    /// `EquipmentRepository.save(_:)` already promises not to write the flag "whatever the record
    /// carries". Leaving it out here is what makes that promise structural rather than a clause a
    /// save has to remember to honour by restoring the column afterwards: with `G-2.5` forbidding
    /// the unique constraint that would notice, two rows claiming the flag is a bug nothing else
    /// catches.
    ///
    /// `init(record:)` *does* write it, because a new row has no previous value to keep and a
    /// restore has to reinstate the one the backup carried.
    func update(from record: EquipmentProfile) {
        name = record.name
        barWeightGrams = record.barWeight.grams
        collarWeightGrams = record.collarWeight.grams
        replaceInventory(
            plateGrams: record.plates.map(\.grams), platePairCounts: record.platePairCounts)
    }
}

extension UserSettingsEntity: RecordMappable {
    /// This row as a record.
    var record: UserSettings {
        UserSettings(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            userID: userID,
            displayUnit: RecordVocabulary.resolve(
                displayUnitRawValue, or: RecordVocabulary.displayUnit),
            e1RMFormula: RecordVocabulary.resolve(
                e1RMFormulaRawValue, or: RecordVocabulary.e1RMFormula),
            theme: RecordVocabulary.resolve(themeRawValue, or: RecordVocabulary.theme),
            defaultRoundingIncrement: Weight(grams: defaultRoundingIncrementGrams),
            defaultRoundingStrategy: RecordVocabulary.resolve(
                defaultRoundingStrategyRawValue, or: RecordVocabulary.roundingStrategy)
        )
    }

    /// A new row carrying `record`.
    convenience init(record: UserSettings) {
        self.init(
            id: record.id,
            userID: record.userID,
            displayUnit: record.displayUnit,
            e1RMFormula: record.e1RMFormula,
            theme: record.theme,
            defaultRoundingIncrementGrams: record.defaultRoundingIncrement.grams,
            defaultRoundingStrategy: record.defaultRoundingStrategy,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    /// Overwrites this row's preferences from `record`, preserving an unmappable stored spelling.
    ///
    /// **``userID`` is not written, and it is not an omission.** `TR-1.10` mints it once and
    /// `FR-5.1.2` claims every local row with it, so a layer able to rewrite it could hand the
    /// user's history to another identity. A save carrying a different one is refused rather than
    /// ignored — see `RepositoryError.identityAlreadyEstablished(recordID:)` — and that comparison
    /// is the repository's, which is why this mapping has nothing to say about it.
    func update(from record: UserSettings) {
        displayUnitRawValue = preservingRawValue(
            record.displayUnit, stored: displayUnitRawValue, fallback: RecordVocabulary.displayUnit)
        e1RMFormulaRawValue = preservingRawValue(
            record.e1RMFormula,
            stored: e1RMFormulaRawValue,
            fallback: RecordVocabulary.e1RMFormula)
        themeRawValue = preservingRawValue(
            record.theme, stored: themeRawValue, fallback: RecordVocabulary.theme)
        defaultRoundingIncrementGrams = record.defaultRoundingIncrement.grams
        defaultRoundingStrategyRawValue = preservingRawValue(
            record.defaultRoundingStrategy,
            stored: defaultRoundingStrategyRawValue,
            fallback: RecordVocabulary.roundingStrategy)
    }
}

extension PersonalRecordCacheEntity: RecordMappable {
    /// This row as a record.
    var record: PersonalRecordCache {
        PersonalRecordCache(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            exerciseID: exerciseID,
            repCount: repCount,
            weight: Weight(grams: weightGrams),
            sourceSetID: sourceSetID,
            achievedAt: achievedAt,
            computationVersion: computationVersion
        )
    }

    /// A new row carrying `record`.
    convenience init(record: PersonalRecordCache) {
        self.init(
            id: record.id,
            exerciseID: record.exerciseID,
            repCount: record.repCount,
            weightGrams: record.weight.grams,
            sourceSetID: record.sourceSetID,
            achievedAt: record.achievedAt,
            computationVersion: record.computationVersion,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    /// Overwrites this row from `record`.
    func update(from record: PersonalRecordCache) {
        exerciseID = record.exerciseID
        repCount = record.repCount
        weightGrams = record.weight.grams
        sourceSetID = record.sourceSetID
        achievedAt = record.achievedAt
        computationVersion = record.computationVersion
    }
}
