import Foundation
import PowerliftingCore

/// One target weight/rep/set group planned for an exercise in a session — the routine's target as
/// it stood when the workout was started (`TR-15.3`, `FR-15.2.3`).
///
/// **A copy, not a reference, and that is the whole point of the type.** A session started from a
/// routine takes the targets the routine prescribed *at that moment* and stores them against its
/// own exercise entry. Editing the routine afterwards rewrites the plan for the next workout and
/// leaves this one alone, which a stored routine identifier could not promise: the row it named
/// would answer with today's numbers when a past session asked what it had been told to lift.
///
/// **The weight is already resolved.** ``RoutineTargetGroup/prescription`` was put through
/// ``PowerliftingCore/PrescriptionResolver`` on the way here, so this carries the number rather
/// than the instruction that produced it — a prescription re-resolved later would explain an old
/// session with today's history.
///
/// **A blank weight is `nil`, and it is not the same fact as zero** — ``RoutineTargetGroup``'s
/// distinction, carried across intact (`FR-15.2.2`). ``targetReps`` and ``targetSets`` are
/// prescribed either way.
///
/// **Independent of what was logged** (`FR-15.2.4`): the sets under the same entry record what was
/// actually done and are constrained by nothing here.
public struct PlannedTargetGroup: StoredRecord {
    /// See ``StoredRecord/id``.
    public let id: UUID

    /// See ``StoredRecord/createdAt``.
    public let createdAt: Date

    /// See ``StoredRecord/updatedAt``.
    public let updatedAt: Date

    /// See ``StoredRecord/deletedAt``.
    public let deletedAt: Date?

    /// The ``ExerciseEntry`` this group was planned for.
    ///
    /// A plain `UUID`: the schema declares no relationships (`G-2.5`), so nothing but a repository
    /// write enforces that the row exists.
    public let exerciseEntryID: UUID

    /// Position within the exercise, ascending — the top set before the backoff, for instance.
    public let order: Int

    /// The load on **one** implement, or `nil` where the plan named none. See this type's note.
    public let targetWeight: Weight?

    /// Reps prescribed per set in this group.
    public let targetReps: Int

    /// Sets prescribed in this group.
    public let targetSets: Int

    /// Creates a planned-target record. No property is validated; see this module's header.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        exerciseEntryID: UUID,
        order: Int,
        targetWeight: Weight?,
        targetReps: Int,
        targetSets: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.exerciseEntryID = exerciseEntryID
        self.order = order
        self.targetWeight = targetWeight
        self.targetReps = targetReps
        self.targetSets = targetSets
    }
}

// MARK: - Codable

extension PlannedTargetGroup {
    /// The wire format's keys, in the order they are written. See `RecordCoding.swift`.
    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case deletedAt
        case exerciseEntryID
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
            exerciseEntryID: try container.decode(UUID.self, forKey: .exerciseEntryID),
            order: try container.decode(Int.self, forKey: .order),
            targetWeight: try container.decodeIfPresent(Weight.self, forKey: .targetWeight),
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
        try container.encode(exerciseEntryID, forKey: .exerciseEntryID)
        try container.encode(order, forKey: .order)
        try container.encodeIfPresent(targetWeight, forKey: .targetWeight)
        try container.encode(targetReps, forKey: .targetReps)
        try container.encode(targetSets, forKey: .targetSets)
    }
}
