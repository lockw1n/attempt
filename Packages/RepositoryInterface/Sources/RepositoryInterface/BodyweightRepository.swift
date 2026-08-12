import Foundation
import PowerliftingCore

/// The bodyweight log (`TR-0.4.1`, `FR-1.8`).
///
/// Separate from `WorkoutSession.bodyweight`, which is the weight recorded alongside a session:
/// this log exists on days with no training on them.
public protocol BodyweightRepository: Sendable {
    /// Readings whose ``BodyweightEntry/date`` falls in `range`, newest first (`FR-1.8.3`).
    ///
    /// `FR-1.8.3`'s 7-day rolling average is computed from this, so a caller asking for a window
    /// needs the six days before it too — the repository does not widen the range on its own.
    func entries(in range: ClosedRange<Date>, includingDeleted: Bool) async throws -> [BodyweightEntry]

    /// One reading, or `nil` if no row carries that id.
    func entry(id: UUID, includingDeleted: Bool) async throws -> BodyweightEntry?

    /// Inserts or replaces the reading, keyed on ``BodyweightEntry/id`` (`FR-1.8.1`).
    ///
    /// **No de-duplication happens here.** `FR-1.8.2` de-duplicates HealthKit readings against
    /// manual ones, which is a rule about a window and a source rather than about a row, and a
    /// repository that quietly dropped a save would make the import that called it unable to
    /// report what it did.
    func save(_ entry: BodyweightEntry) async throws

    /// Soft-deletes one reading.
    ///
    /// - Throws: ``RepositoryError/recordNotFound(id:)`` if no live reading carries that id.
    func deleteEntry(id: UUID) async throws
}
