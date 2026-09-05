import Foundation

/// One pass through a program: which week it is on, and which day comes next (`FR-16.8.3`).
///
/// **A row rather than three columns on ``Program``, because `FR-16.8.4` needs one to end and one
/// to begin.** *Start next week* closes the run in progress and opens the next, so the week a
/// session belonged to survives the advance — where a counter on the program would be overwritten
/// by it, and every session already logged would silently re-describe itself as belonging to the
/// current week.
///
/// **This is what `WorkoutSession.programRunID` has always pointed at.** The column has existed
/// since schema v1 as a forward reference; it names a run rather than a program because a lifter
/// running the same program twice is two passes, and a session belongs to one of them.
///
/// **``weekNumber`` and ``nextDayIndex`` are separate numbers that happen to look alike.** The first
/// is the week the lifter is in — the `#2` of the author's plan file — and the second is a cursor
/// into ``ProgramDay/order``. They move independently: three days finished advances the cursor three
/// times and the week once.
public struct ProgramRun: StoredRecord {
    /// See ``StoredRecord/id``.
    public let id: UUID

    /// See ``StoredRecord/createdAt``.
    public let createdAt: Date

    /// See ``StoredRecord/updatedAt``.
    public let updatedAt: Date

    /// See ``StoredRecord/deletedAt``.
    public let deletedAt: Date?

    /// The ``Program`` being run.
    public let programID: UUID

    /// When this pass began.
    ///
    /// **Not ``createdAt``**, which is when the row was written: a run restored from a backup, or
    /// one the lifter backdated, has the two disagree, and only this one orders the passes.
    public let startedAt: Date

    /// When it finished, or `nil` while it is the run in force.
    ///
    /// `nil` is the whole of what "current" means here — see
    /// ``ProgramRepository/currentRun()``. There is no `isCurrent` column, because a second
    /// row could then contradict it (`G-1.4`).
    public let endedAt: Date?

    /// The week the lifter is on — the `#N` of a plan file, not an index.
    public let weekNumber: Int

    /// The ``ProgramDay/order`` of the day to train next.
    public let nextDayIndex: Int

    /// Creates a program-run record. No property is validated; see this module's header.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        programID: UUID,
        startedAt: Date,
        endedAt: Date?,
        weekNumber: Int,
        nextDayIndex: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.programID = programID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.weekNumber = weekNumber
        self.nextDayIndex = nextDayIndex
    }

    /// Whether this run is still open — the property ``ProgramRepository/currentRun()`` resolves on.
    public var isOpen: Bool { endedAt == nil && !isSoftDeleted }
}

// MARK: - Codable

extension ProgramRun {
    /// The wire format's keys, in the order they are written. See `RecordCoding.swift`.
    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case deletedAt
        case programID
        case startedAt
        case endedAt
        case weekNumber
        case nextDayIndex
    }

    /// Decodes the keyed shape on ``CodingKeys``. Nothing is validated.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt),
            programID: try container.decode(UUID.self, forKey: .programID),
            startedAt: try container.decode(Date.self, forKey: .startedAt),
            endedAt: try container.decodeIfPresent(Date.self, forKey: .endedAt),
            weekNumber: try container.decode(Int.self, forKey: .weekNumber),
            nextDayIndex: try container.decode(Int.self, forKey: .nextDayIndex)
        )
    }

    /// Writes the nine keys in declaration order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(programID, forKey: .programID)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encode(weekNumber, forKey: .weekNumber)
        try container.encode(nextDayIndex, forKey: .nextDayIndex)
    }
}
