import Foundation
import PowerliftingCore

/// One bodyweight reading as an outside source reports it (`FR-1.8.2`).
///
/// Not a ``RepositoryInterface/BodyweightEntry``: a sample has no place in the log yet, and
/// ``HealthBodyweightImport`` is what decides which of them become rows and under whose identity.
public struct BodyweightSample: Hashable, Sendable {
    /// The source's own identity for this reading.
    ///
    /// **Stable across reads of the same sample**, which is what makes re-importing idempotent: a
    /// sample seen twice arrives under one id and replaces its row instead of doubling it.
    public let id: UUID

    /// When the reading was taken — a real instant, not a day.
    public let date: Date

    /// What was weighed.
    public let weight: Weight

    /// Creates a sample. Nothing is validated; the planner decides what is usable.
    ///
    /// - Parameters:
    ///   - id: The source's identity for this reading.
    ///   - date: When it was taken.
    ///   - weight: What was weighed.
    public init(id: UUID, date: Date, weight: Weight) {
        self.id = id
        self.date = date
        self.weight = weight
    }

    /// A reading a source reports in kilograms, as the sample it becomes — or `nil` where it is
    /// not a weight this app can store.
    ///
    /// **Whole grams, rounded to nearest** (`G-1.1`): an outside source answers a `Double` and
    /// grams are the only representation stored, so the crossing happens once, here. A value no
    /// scale produces is refused rather than stored as something else.
    ///
    /// It lives on the sample rather than inside the reader because the reader is compiled only
    /// where a health framework exists, and this arithmetic is the whole of what it does that can
    /// be wrong.
    ///
    /// - Parameters:
    ///   - kilograms: What the source reported.
    ///   - id: The source's identity for the reading.
    ///   - date: When it was taken.
    /// - Returns: The sample, or `nil` where the value is not storable.
    public static func fromKilograms(_ kilograms: Double, id: UUID, date: Date) -> Self? {
        guard let weight = Weight(kilograms: kilograms, rounding: .nearest) else { return nil }
        return Self(id: id, date: date, weight: weight)
    }
}

/// Where `FR-1.8.2`'s readings come from — HealthKit in the app, a fake in a test.
///
/// **A protocol so this module names no Apple health framework.** `TR-1.3` puts the screen here and
/// `G-5.4` says the data never leaves the device; both are easier to hold when the only thing the
/// state knows is two calls that answer readings.
///
/// **Authorization is separate from reading, and only the first one prompts.** `TR-1.9`'s prompt is
/// owed on first use of this feature and never at launch, so nothing calls ``authorize()`` until a
/// person asks for an import.
public protocol BodyweightSampleSource {
    /// Whether this device has the source at all. `false` hides the command rather than failing it.
    var isAvailable: Bool { get }

    /// Asks for read access to body mass, and nothing else.
    ///
    /// **Returning without throwing does not mean access was granted.** A read authorization is
    /// deliberately not disclosed — telling an app that a person refused is itself a disclosure —
    /// so a refusal is indistinguishable from a source holding no readings. Copy that reports an
    /// import must say what arrived, never what was allowed.
    func authorize() async throws

    /// Every bodyweight reading the source will disclose, in any order.
    func samples() async throws -> [BodyweightSample]
}
