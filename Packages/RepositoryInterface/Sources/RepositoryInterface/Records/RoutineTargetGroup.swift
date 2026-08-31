import Foundation
import PowerliftingCore

/// One target weight/rep/set group within a routine's exercise slot (`FR-15.2.1`'s amendment) — a
/// slot may carry more than one, e.g. `80×5×4` then `90×4×4` as a top set and a backoff.
///
/// **``targetWeight`` mirrors the stored column, not ``PowerliftingCore/Prescription``.** This
/// slice writes only `Prescription`'s `.fixedWeight` payload, so the column *is* that payload; see
/// ``prescription`` for the projection that hands it back as the domain type. A second
/// `Prescription` case reaching this slot is a schema change and a new record property, not a
/// change to this one.
public struct RoutineTargetGroup: StoredRecord {
    /// See ``StoredRecord/id``.
    public let id: UUID

    /// See ``StoredRecord/createdAt``.
    public let createdAt: Date

    /// See ``StoredRecord/updatedAt``.
    public let updatedAt: Date

    /// See ``StoredRecord/deletedAt``.
    public let deletedAt: Date?

    /// The ``RoutineExercise`` this group belongs to.
    public let routineExerciseID: UUID

    /// Position within the slot, ascending — the top set before the backoff, for instance.
    public let order: Int

    /// The load on **one** implement. See this type's note.
    public let targetWeight: Weight

    /// Reps prescribed per set in this group.
    public let targetReps: Int

    /// Sets prescribed in this group.
    public let targetSets: Int

    /// Creates a target-group record. No property is validated; see this module's header.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        routineExerciseID: UUID,
        order: Int,
        targetWeight: Weight,
        targetReps: Int,
        targetSets: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.routineExerciseID = routineExerciseID
        self.order = order
        self.targetWeight = targetWeight
        self.targetReps = targetReps
        self.targetSets = targetSets
    }
}

// MARK: - Projection

extension RoutineTargetGroup {
    /// This group's load as `TR-0.2.10`'s domain type, ready for
    /// ``PowerliftingCore/PrescriptionResolver``.
    ///
    /// Never fails: `.fixedWeight` accepts any ``PowerliftingCore/Weight``, including a negative
    /// one (assisted work). The one case this slice can store is the one case this returns — see
    /// this type's note.
    public var prescription: Prescription {
        .fixedWeight(targetWeight)
    }
}

// MARK: - Codable

extension RoutineTargetGroup {
    /// The wire format's keys, in the order they are written. See `RecordCoding.swift`.
    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case deletedAt
        case routineExerciseID
        case order
        case targetWeight
        case targetReps
        case targetSets
    }

    /// Decodes the keyed shape on ``CodingKeys``. Nothing is validated.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt),
            routineExerciseID: try container.decode(UUID.self, forKey: .routineExerciseID),
            order: try container.decode(Int.self, forKey: .order),
            targetWeight: try container.decode(Weight.self, forKey: .targetWeight),
            targetReps: try container.decode(Int.self, forKey: .targetReps),
            targetSets: try container.decode(Int.self, forKey: .targetSets)
        )
    }

    /// Writes the nine keys in declaration order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(routineExerciseID, forKey: .routineExerciseID)
        try container.encode(order, forKey: .order)
        try container.encode(targetWeight, forKey: .targetWeight)
        try container.encode(targetReps, forKey: .targetReps)
        try container.encode(targetSets, forKey: .targetSets)
    }
}
