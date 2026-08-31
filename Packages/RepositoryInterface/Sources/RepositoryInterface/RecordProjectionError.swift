import Foundation
import PowerliftingCore

/// Why a stored row could not be interpreted as the domain type it describes.
///
/// **Distinct from ``RepositoryError``, and the distinction is the whole of rule 4.** That type is
/// what a *write* is refused with; this is what an *interpretation* is refused with. Neither is
/// raised by a read: a record mirrors its row whatever the row says, so the columns arrive intact
/// and only fail when something asks what they mean. A caller listing a user's equipment profiles
/// never has to handle one of these; a caller loading plates onto a bar does.
///
/// **Every case names `recordID` and the offending value**, because the caller these exist for is
/// `FR-1.11.3`'s repair: an error saying only "invalid inventory" leaves the user with a profile
/// they cannot fix and an app that will not use it. Dropping the offending denomination instead
/// would be worse than either — `PlateCalculator` would then propose a loading the gym cannot make.
public enum RecordProjectionError: Error, Sendable, Hashable {
    /// A profile's two plate lists are different lengths, so no denomination can be paired with a
    /// count. What a synced profile looks like when one of the two CloudKit fields arrived and the
    /// other did not.
    case plateListsDisagreeInLength(recordID: UUID, plates: Int, pairCounts: Int)

    /// A profile lists a denomination lighter than one gram, which is not a plate.
    case plateUnderOneGram(recordID: UUID, plate: Weight)

    /// A profile claims a negative number of pairs of a denomination. Zero is legal; below it is
    /// not.
    case negativePlatePairCount(recordID: UUID, plate: Weight, pairs: Int)

    /// A profile lists one denomination twice.
    ///
    /// Refused rather than summed: two entries for 20 kg is far more likely a duplicated row than a
    /// statement about two sets of 20s, and summing would make the mistake invisible.
    case repeatedPlateDenomination(recordID: UUID, plate: Weight)

    /// A profile's total plate mass does not fit in `Int` grams. Rejecting it here is what lets
    /// every later loading calculation add plate masses without re-checking.
    case plateInventoryOverflows(recordID: UUID)

    /// A training-max row's source names a payload column that is `nil` — `.manual` with no manual
    /// weight, or `.percentOfRepMax` with no rep count.
    ///
    /// This is what a row this app did not write looks like, and the schema's default source is
    /// `.manual` precisely so that it lands here rather than quietly resolving to 90% of the user's
    /// e1RM.
    case trainingMaxPayloadMissing(recordID: UUID, source: TrainingMaxSourceKind)

    /// A training-max row's percentage is not a finite ratio greater than zero. `0.9` is 90%; a
    /// stored `90` is a 9000% training max rather than the same number in other clothes.
    case trainingMaxPercentageUnusable(recordID: UUID, percentage: ReportedNumber)

    /// A rounding increment below one gram, which maps to no `RoundingRule`. Raised by both the
    /// training-max projection and the settings one; `recordID` says which row.
    case roundingIncrementUnloadable(recordID: UUID, increment: Weight)

    /// A set's rep count is negative. Zero is legal and meaningful — a failed set records the reps
    /// actually achieved, which can be none.
    case repsOutOfRange(recordID: UUID, reps: Int)

    /// A set's RPE falls outside 1…10, the interval the scale is defined over.
    case rpeOutOfRange(recordID: UUID, rpe: ReportedNumber)

    /// A set's RIR falls outside 0…9. Derived from the RPE range rather than chosen: the two are
    /// one scale related by `rir = 10 - rpe`.
    case rirOutOfRange(recordID: UUID, rir: Int)

    /// A set was refused by `SetRecord` for a reason this version cannot name.
    ///
    /// **Unreachable today and deliberately kept.** The three cases above are `SetRecord`'s three
    /// guards, read from its own published ranges rather than from copies of them — but a fourth
    /// guard added there would otherwise surface here as one of the three, naming a field that is
    /// not the problem. A refusal that lies about which column to fix is worse than one that admits
    /// it does not know.
    case setRefusedByDomainType(recordID: UUID)

    /// A training-max row was refused by `TrainingMaxConfiguration` for a reason this version cannot
    /// name. The counterpart of ``setRefusedByDomainType(recordID:)``, and unreachable for the same
    /// reason: that type refuses exactly one thing today, so the percentage case above is currently
    /// the only outcome.
    case trainingMaxRefusedByDomainType(recordID: UUID)
}

/// A number a refusal reports, compared so that a value always equals itself.
///
/// **A wrapper rather than a bare `Double`, and the reason is NaN.** ``RecordProjectionError`` is
/// `Hashable`, and the two cases carrying one of these exist to report a number that is not usable
/// — NaN included, since `SetRecord` rejects a NaN RPE and `TrainingMaxConfiguration` a non-finite
/// percentage. With a bare `Double` the synthesised `==` is **not reflexive on exactly the values
/// those cases are raised for**: a repair caller collecting refusals into a `Set` gets one entry per
/// occurrence, and `contains` is false for an error it has just inserted.
///
/// A wrapper rather than a hand-written `==` on the enum, so that a case added later inherits the
/// fix instead of having to be remembered into a switch — and so the comparison is one expression
/// rather than one arm per case.
///
/// Comparing by `Double.bitPattern` is stricter than `Double.==` in two ways, both harmless
/// here: two NaNs with different payloads are different refusals, and `0.0` differs from `-0.0`.
public struct ReportedNumber: Sendable, Hashable, CustomStringConvertible {
    /// The number as the row held it. Any `Double`, NaN and the infinities included.
    public let value: Double

    /// Wraps a number a refusal is reporting.
    public init(_ value: Double) {
        self.value = value
    }

    /// A NaN, for the refusals a non-finite value produces.
    public static let nan = ReportedNumber(.nan)

    /// Equal exactly when the two bit patterns are — see this type's note.
    public static func == (lhs: ReportedNumber, rhs: ReportedNumber) -> Bool {
        lhs.value.bitPattern == rhs.value.bitPattern
    }

    /// Hashes the bit pattern, so that equality and hashing agree on NaN.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(value.bitPattern)
    }

    /// The wrapped number. Diagnostic output, not a display string.
    public var description: String {
        "\(value)"
    }
}

extension ReportedNumber: ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    /// Lets a call site write `rpe: 10.5`.
    public init(floatLiteral value: Double) {
        self.init(value)
    }

    /// Lets a call site write `percentage: 0`.
    public init(integerLiteral value: Int) {
        self.init(Double(value))
    }
}
