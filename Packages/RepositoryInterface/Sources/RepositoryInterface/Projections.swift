// The four fallible projections — the only places in this module anything is refused on account of
// what a row says, and the reason a record may mirror its row without validating it (TR-0.4.4,
// FR-1.11.3).
//
// A record comes back whole from every read. Asking one what it *means* is a separate act, it is
// the act that can fail, and it fails without costing the record: a profile whose plate lists
// disagree still has its name, its bar and its collars, and a training-max row whose source names a
// missing payload still has its effective date and its dormant configuration. Nothing here mutates,
// drops or repairs anything — see `RecordProjectionError` for why dropping the offending value
// would be the worst of the three.
//
// THERE ARE FOUR, NOT THREE. The fourth is `UserSettings.defaultRounding()`, and it exists for the
// same reason the other three do: `defaultRoundingIncrement` is stored unvalidated, so a value
// below one gram maps to no `RoundingRule` and the refusal has nowhere else to live.
//
// EVERY REFUSAL IS THE DOMAIN TYPE'S, NOT A COPY OF IT. The ranges are read from `SetRecord`'s own
// published constants and the guards are the ones `PlateInventory`, `RoundingRule` and
// `TrainingMaxConfiguration` publish; a second copy here would be a boundary that drifts from the
// type it is defending.

import Foundation
import PowerliftingCore

extension EquipmentProfile {
    /// The plate denominations this profile stocks, as the domain type that loads a bar.
    ///
    /// - Returns: The inventory, normalised heaviest-first by `PlateInventory` itself.
    /// - Throws: A `RecordProjectionError` naming the offending denomination, or the pairing, when
    ///   the two stored lists cannot describe a gym.
    public func inventory() throws(RecordProjectionError) -> PlateInventory {
        guard plates.count == platePairCounts.count else {
            throw .plateListsDisagreeInLength(
                recordID: id, plates: plates.count, pairCounts: platePairCounts.count)
        }

        var seen: Set<Int> = []
        for (plate, pairs) in zip(plates, platePairCounts) {
            guard plate.grams >= 1 else { throw .plateUnderOneGram(recordID: id, plate: plate) }
            guard pairs >= 0 else {
                throw .negativePlatePairCount(recordID: id, plate: plate, pairs: pairs)
            }
            guard seen.insert(plate.grams).inserted else {
                throw .repeatedPlateDenomination(recordID: id, plate: plate)
            }
        }

        let entries = zip(plates, platePairCounts).map { PlateInventory.Entry(plate: $0, pairs: $1) }
        // The only refusal left to `PlateInventory` once the three above have passed, and it is
        // reachable rather than defensive: a denomination and a pair count that are each plausible
        // can still multiply out past `Int`.
        guard let inventory = PlateInventory(entries: entries) else {
            throw .plateInventoryOverflows(recordID: id)
        }
        return inventory
    }
}

extension TrainingMaxEntry {
    /// How this row says a training max is computed, as the domain type that resolves one.
    ///
    /// **The manual weight is a parameter rather than a column**, which is the whole of `G-1.4` on
    /// this record: the entered number is ``TrainingMaxHistoryEntry``'s, so a caller resolving a
    /// manual configuration passes the value in force on the date it is asking about. A caller with
    /// none passes `nil` and is refused, which is the same refusal a `.manual` row with no payload
    /// used to raise — moved to where the payload now is rather than dropped.
    ///
    /// The payloads are paired with ``TrainingMaxEntry/source`` here and nowhere else, and the
    /// schema's default source is `.manual` so that a row this app did not write refuses here rather
    /// than resolving to a plausible number.
    ///
    /// - Parameter manualWeight: The training max in force, for a manual source. Ignored for the
    ///   other two — a derived source computes its own number, and a value passed alongside one
    ///   would be a second answer this projection has no business preferring.
    /// - Returns: The configuration, with the percentage and rounding rule carried whatever the
    ///   source, since a manual training max keeps both as the configuration its one-tap
    ///   recalculation resumes with (`FR-1.5.1.5`).
    /// - Throws: A `RecordProjectionError` for a missing payload, an unusable percentage, or an
    ///   increment below one gram.
    public func configuration(
        manualWeight: Weight?
    ) throws(RecordProjectionError) -> TrainingMaxConfiguration {
        let resolvedSource: TrainingMaxSource
        switch source {
        case .percentOfE1RM:
            resolvedSource = .percentOfE1RM
        case .percentOfRepMax:
            guard let sourceRepCount else {
                throw .trainingMaxPayloadMissing(recordID: id, source: source)
            }
            resolvedSource = .percentOfRepMax(reps: sourceRepCount)
        case .manual:
            guard let manualWeight else {
                throw .trainingMaxPayloadMissing(recordID: id, source: source)
            }
            resolvedSource = .manual(manualWeight)
        }

        guard let rounding = RoundingRule(increment: roundingIncrement, strategy: roundingStrategy) else {
            throw .roundingIncrementUnloadable(recordID: id, increment: roundingIncrement)
        }

        // The refusal is the domain type's and the attribution is this layer's — deliberately in
        // that order, so the percentage is never *gated* here, only *named* when the construction
        // has already failed. `TrainingMaxConfiguration` refuses exactly one thing today, so the
        // second branch is unreachable; a guard added there reports honestly instead of blaming a
        // percentage that is fine. Same reasoning as `setRefusedByDomainType` below.
        guard
            let configuration = TrainingMaxConfiguration(
                source: resolvedSource,
                percentage: percentage,
                rounding: rounding,
                progressionIncrement: progressionIncrement)
        else {
            throw percentage.isFinite && percentage > 0
                ? .trainingMaxRefusedByDomainType(recordID: id)
                : .trainingMaxPercentageUnusable(recordID: id, percentage: ReportedNumber(percentage))
        }
        return configuration
    }
}

extension UserSettings {
    /// The loadable step and direction a new exercise inherits (`FR-1.5.1.6`).
    ///
    /// - Returns: The rule the two stored columns describe.
    /// - Throws: `RecordProjectionError.roundingIncrementUnloadable(recordID:increment:)` when the
    ///   increment is below one gram. The strategy cannot fail — an unreadable spelling has already
    ///   resolved by the time a caller holds the record.
    public func defaultRounding() throws(RecordProjectionError) -> RoundingRule {
        guard
            let rule = RoundingRule(
                increment: defaultRoundingIncrement, strategy: defaultRoundingStrategy)
        else {
            throw .roundingIncrementUnloadable(recordID: id, increment: defaultRoundingIncrement)
        }
        return rule
    }
}

extension SetEntry {
    /// This set as the analytical value type every formula reads (`TR-0.2.3`).
    ///
    /// Drops what the formulas do not read — identity, ordering, targets, the note and the
    /// completion timestamp — so it is a projection in both senses. `modifiers` survives, raw
    /// spellings included.
    ///
    /// - Returns: The set as `SetRecord` sees it.
    /// - Throws: A `RecordProjectionError` naming the field outside its range.
    public func setRecord() throws(RecordProjectionError) -> SetRecord {
        guard SetRecord.repsRange.contains(reps) else {
            throw .repsOutOfRange(recordID: id, reps: reps)
        }
        if let rpe, !SetRecord.rpeRange.contains(rpe) {
            throw .rpeOutOfRange(recordID: id, rpe: ReportedNumber(rpe))
        }
        if let rir, !SetRecord.rirRange.contains(rir) {
            throw .rirOutOfRange(recordID: id, rir: rir)
        }
        guard
            let record = SetRecord(
                weight: weight,
                reps: reps,
                rpe: rpe,
                rir: rir,
                isWarmup: isWarmup,
                isCompleted: isCompleted,
                modifiers: modifiers)
        else {
            throw .setRefusedByDomainType(recordID: id)
        }
        return record
    }
}
