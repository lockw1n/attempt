import Foundation
import PowerliftingCore

/// One bodyweight reading (`TR-0.3.5`).
public struct BodyweightEntry: StoredRecord {
    /// See ``StoredRecord/id``.
    public let id: UUID

    /// See ``StoredRecord/createdAt``.
    public let createdAt: Date

    /// See ``StoredRecord/updatedAt``.
    public let updatedAt: Date

    /// See ``StoredRecord/deletedAt``.
    public let deletedAt: Date?

    /// The day the reading is for, which is not necessarily when it was entered (`FR-1.8.1`).
    public let date: Date

    /// The reading. Signed by type; a real one is not.
    public let weight: Weight

    /// Where the reading came from — what `FR-1.8.2`'s de-duplication of HealthKit readings
    /// against manual ones keys on.
    public let source: BodyweightSource

    /// Creates a bodyweight record. No property is validated; see this module's header.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        date: Date,
        weight: Weight,
        source: BodyweightSource
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.date = date
        self.weight = weight
        self.source = source
    }
}
