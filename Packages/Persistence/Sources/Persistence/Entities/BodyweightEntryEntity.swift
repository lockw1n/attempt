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

// `StoredEntity` requires these four per concrete type and supplies no default. The reason is on
// the protocol's own requirements, and it is not a style preference: a `#Predicate` written in a
// generic context captures a key path the optimizer may re-instantiate, which fetches correctly
// unoptimized and traps under `-O`.
extension BodyweightEntryEntity {
    static func matchingID(_ id: UUID) -> Predicate<BodyweightEntryEntity> {
        #Predicate<BodyweightEntryEntity> { $0.id == id }
    }

    static var notDeleted: Predicate<BodyweightEntryEntity> {
        #Predicate<BodyweightEntryEntity> { $0.deletedAt == nil }
    }

    static func notDeleted(
        alsoMatching other: Predicate<BodyweightEntryEntity>
    ) -> Predicate<BodyweightEntryEntity> {
        #Predicate<BodyweightEntryEntity> { entity in
            other.evaluate(entity) && entity.deletedAt == nil
        }
    }

    static func softDeleted(onOrBefore cutoff: Date) -> Predicate<BodyweightEntryEntity> {
        #Predicate<BodyweightEntryEntity> { entity in
            if let deletedAt = entity.deletedAt {
                return deletedAt <= cutoff
            } else {
                return false
            }
        }
    }
}
