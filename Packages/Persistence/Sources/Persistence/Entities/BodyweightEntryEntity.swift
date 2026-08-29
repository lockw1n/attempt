import Foundation
import RepositoryInterface
import SwiftData

/// One bodyweight reading (`TR-0.3.5`).
///
/// Distinct from `WorkoutSessionEntity.bodyweightGrams`, which is the weight recorded *alongside* a
/// session: this is the bodyweight log `FR-1.8.3` lists and `FR-3.5.1` charts, and it exists on days
/// with no training on them.
@Model
final class BodyweightEntryEntity: StoredEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// The day the reading is for, which is not necessarily when it was entered.
    var date: Date = SchemaDefaults.bodyweightDate

    /// The reading, in grams (`G-1.1`).
    var weightGrams: Int = 0

    /// ``RepositoryInterface/BodyweightSource``'s raw value — `TR-0.3.5`'s `source`, and what `FR-1.8.2`'s
    /// de-duplication of HealthKit readings against manual ones keys on.
    var sourceRawValue: String = SchemaDefaults.bodyweightSource

    init(
        id: UUID = UUID(),
        date: Date,
        weightGrams: Int,
        source: BodyweightSource,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.weightGrams = weightGrams
        self.sourceRawValue = source.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
