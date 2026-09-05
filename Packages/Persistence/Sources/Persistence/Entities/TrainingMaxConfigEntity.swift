import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData

/// How one exercise's training max is computed, from a given date (`TR-0.3.6`, `FR-1.5.1.1`).
///
/// **The number is not here.** A manual training max is a ``TrainingMaxHistoryEntity`` row, dated
/// and annotated (`FR-1.5.1.4`, `FR-16.7.2`), and this table says only how a number is arrived at. A
/// value column beside the history would be a value that can disagree with it, which is exactly what
/// `G-1.4` refuses; the in-force read is a lookup over the history and never a read of a stored
/// answer.
///
/// **``sourceRawValue`` is the only column that says which of the others took part in the number.**
/// A manual training max is the weight the lifter entered, with neither ``percentage`` nor the two
/// rounding columns applied (`FR-1.5.1.5`) — but all three are still written, still read back, and
/// hold values indistinguishable from a derived row's. That is deliberate rather than untidy:
///
/// - **They are the configuration, not the calculation.** `FR-1.5.1.5` makes manual an *override*
///   with a one-tap "recalculate from e1RM", and an override that discarded the percentage and rule
///   it overrides could not be undone in one tap.
/// - **No in-band marker is available.** The values that would mean "did not participate" — a zero
///   percentage, a zero increment — are exactly the ones `TrainingMaxConfiguration` and
///   `RoundingRule` refuse, so a row wearing one could not be mapped to a configuration at all.
///
/// So a reader may not infer participation from these columns' *values*, in either direction. Ask
/// ``sourceRawValue``. `init` requires all three whatever the source, so a manual row states its
/// dormant configuration rather than inheriting whatever the last screen happened to hold.
///
/// **``incrementGrams`` is not the rounding increment**, and mistaking the two inflates every
/// training max by one step per read: it is `FR-1.5.1.3`'s block-completion progression, which a
/// resolution carries and never applies.
///
/// Whether ``sourceRepCount`` is meaningful also follows from ``sourceRawValue``, and nothing here
/// enforces the pairing — a `.percentOfRepMax` row with none is a repository concern (`TR-0.4.3`),
/// as every cross-column invariant in this schema is.
@Model
final class TrainingMaxConfigEntity: StoredEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// The ``ExerciseEntity`` this configures.
    var exerciseID: UUID = SchemaDefaults.unlinkedID

    /// ``RepositoryInterface/TrainingMaxSourceKind``'s raw value — `TR-0.3.6`'s `source`. See the type's note.
    var sourceRawValue: String = SchemaDefaults.trainingMaxSource

    /// The N of a "% of best N-rep max" source, or `nil` for the other two.
    ///
    /// Not in `TR-0.3.6`'s field list, which gives the manual source a payload column and the
    /// rep-max source none — so a user configuring "90% of my best 3-rep max" had nowhere for the 3.
    var sourceRepCount: Int?

    /// The fraction of the source weight to take, as a **ratio**: `0.9` is 90%.
    ///
    /// Persisted the way `TrainingMaxConfiguration` models it, so a row holding `90` would be a
    /// 9000% training max rather than the same number in other clothes. Stored unvalidated, as
    /// `SetEntryEntity.rpe` is: the domain type rejects a non-positive ratio, and this column does
    /// not — which is what makes a row from a foreign store refuse to map rather than map wrongly.
    var percentage: Double = SchemaDefaults.trainingMaxPercentage

    /// The loadable step the scaled weight is snapped to, in grams.
    ///
    /// Unvalidated here too: a value below one gram maps to no `RoundingRule` at all, and the
    /// refusal is the mapping's rather than this column's.
    var roundingIncrementGrams: Int = SchemaDefaults.roundingIncrementGrams

    /// ``PowerliftingCore/RoundingStrategy``'s raw value, the direction half of the same rule.
    var roundingStrategyRawValue: String = SchemaDefaults.roundingStrategy

    /// The step added on successful block completion (`FR-1.5.1.3`), in grams, or `nil` for no
    /// automatic progression.
    ///
    /// Optional where `TR-0.3.6` spells it plain, because `TrainingMaxConfiguration` distinguishes
    /// "no progression configured" from a configured step of zero and a non-optional column cannot.
    /// Negative is a configured deload rather than a mistake.
    var incrementGrams: Int?

    /// When this configuration takes effect. `FR-1.5.1.4` keeps every change, so a lookup reads the
    /// latest row effective on or before the date it is asking about.
    var effectiveFrom: Date = SchemaDefaults.effectiveFrom

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        source: TrainingMaxSourceKind,
        percentage: Double,
        roundingIncrementGrams: Int,
        roundingStrategy: RoundingStrategy,
        effectiveFrom: Date,
        sourceRepCount: Int? = nil,
        incrementGrams: Int? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.sourceRawValue = source.rawValue
        self.percentage = percentage
        self.roundingIncrementGrams = roundingIncrementGrams
        self.roundingStrategyRawValue = roundingStrategy.rawValue
        self.effectiveFrom = effectiveFrom
        self.sourceRepCount = sourceRepCount
        self.incrementGrams = incrementGrams
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
