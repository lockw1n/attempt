import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData
import Testing

@testable import Persistence

// The five supporting entities under a real store. Built through `makeContext(for:)` rather than
// `ModelContainer(...)`: concurrent construction crashes the process, and the helper serialises it.

let supportingSchema = Schema([
    BodyweightEntryEntity.self,
    TrainingMaxConfigEntity.self,
    EquipmentProfileEntity.self,
    UserSettingsEntity.self,
    PersonalRecordCacheEntity.self,
])

func makeSupportingContext() throws -> ModelContext {
    try makeContext(for: supportingSchema)
}

/// A settings row. `userID` carries no default here — `TR-1.10` mints it at first launch and this
/// layer never may, so a fixture that quietly supplied one would be the first exception.
///
/// Every other default differs from the matching `SchemaDefaults` value, so a test asserting one of
/// them cannot be satisfied by the column default it is meant to distinguish from.
func makeSettings(
    userID: UUID,
    displayUnit: MassUnit = .pounds,
    e1RMFormula: E1RMFormulaID = .brzycki,
    theme: ThemePreference = .dark,
    defaultRoundingIncrementGrams: Int = 5000,
    defaultRoundingStrategy: RoundingStrategy = .down,
    displayPrecisionMilliUnits: Int? = 250,
    e1RMLookbackDays: Int = 30,
    keepScreenAwake: Bool = false
) -> UserSettingsEntity {
    UserSettingsEntity(
        userID: userID,
        displayUnit: displayUnit,
        e1RMFormula: e1RMFormula,
        theme: theme,
        defaultRoundingIncrementGrams: defaultRoundingIncrementGrams,
        defaultRoundingStrategy: defaultRoundingStrategy,
        displayPrecisionMilliUnits: displayPrecisionMilliUnits,
        e1RMLookbackDays: e1RMLookbackDays,
        keepScreenAwake: keepScreenAwake
    )
}

/// A training-max configuration with the fields a test is not varying already filled in.
///
/// Every default here differs from the matching `SchemaDefaults` value, so a test asserting one of
/// them cannot be satisfied by the column default it is meant to distinguish from.
func makeTrainingMaxConfig(
    exerciseID: UUID = UUID(),
    source: TrainingMaxSourceKind,
    percentage: Double = 0.85,
    roundingIncrementGrams: Int = 5000,
    roundingStrategy: RoundingStrategy = .down,
    effectiveFrom: Date = Date(timeIntervalSince1970: 1_700_000_000),
    sourceRepCount: Int? = nil,
    manualWeightGrams: Int? = nil,
    incrementGrams: Int? = nil
) -> TrainingMaxConfigEntity {
    TrainingMaxConfigEntity(
        exerciseID: exerciseID,
        source: source,
        percentage: percentage,
        roundingIncrementGrams: roundingIncrementGrams,
        roundingStrategy: roundingStrategy,
        effectiveFrom: effectiveFrom,
        sourceRepCount: sourceRepCount,
        manualWeightGrams: manualWeightGrams,
        incrementGrams: incrementGrams
    )
}

/// An inventory of `pairs` pairs of each denomination, in grams.
func makeInventory(_ denominations: [(grams: Int, pairs: Int)]) throws -> PlateInventory {
    let entries = denominations.map { PlateInventory.Entry(plate: Weight(grams: $0.grams), pairs: $0.pairs) }
    return try #require(PlateInventory(entries: entries))
}

/// A cached N-rep max at the version the calculator currently ships.
func makeCachedRecord(
    exerciseID: UUID,
    repCount: Int,
    weightGrams: Int,
    sourceSetID: UUID = UUID(),
    achievedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    computationVersion: Int = PersonalRecordCalculator.computationVersion
) -> PersonalRecordCacheEntity {
    PersonalRecordCacheEntity(
        exerciseID: exerciseID,
        repCount: repCount,
        weightGrams: weightGrams,
        sourceSetID: sourceSetID,
        achievedAt: achievedAt,
        computationVersion: computationVersion
    )
}
