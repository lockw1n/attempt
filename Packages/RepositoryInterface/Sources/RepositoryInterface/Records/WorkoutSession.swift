import Foundation
import PowerliftingCore

/// One training session (`TR-0.3.2`).
public struct WorkoutSession: StoredRecord {
    /// See ``StoredRecord/id``.
    public let id: UUID

    /// See ``StoredRecord/createdAt``.
    public let createdAt: Date

    /// See ``StoredRecord/updatedAt``.
    public let updatedAt: Date

    /// See ``StoredRecord/deletedAt``.
    public let deletedAt: Date?

    /// The training day this session belongs to, which is not necessarily when it was entered
    /// (`FR-1.2.1` backdates).
    ///
    /// **A correctness input rather than a display field.** It is the first key of the
    /// chronological order a personal-record computation depends on; see
    /// ``WorkoutRepository/sets(forExerciseID:includingDeleted:)``.
    public let date: Date

    /// When the session was started, if it was tracked live (`FR-1.2.11`).
    public let startedAt: Date?

    /// When the session was finished, if it was tracked live.
    public let endedAt: Date?

    /// Session-level notes (`FR-1.2.9`).
    public let notes: String

    /// Bodyweight recorded alongside the session, or `nil` if none was.
    ///
    /// Distinct from ``BodyweightEntry``, which is the log `FR-1.8.3` lists and exists on days with
    /// no training on them.
    public let bodyweight: Weight?

    /// A forward reference to a Phase 2 entity that does not exist yet. Nothing in Phase 0 reads or
    /// writes it (`OUT-0.3` defers the storage, not the field).
    public let programRunID: UUID?

    /// See ``programRunID``.
    public let scheduledWorkoutID: UUID?

    /// The ``ProgramRun/weekNumber`` this session was started under, or `nil` where it was not
    /// started from a program (`FR-16.8.3`).
    ///
    /// **Written once, at start, and never again.** A program edited afterwards — days reordered, a
    /// routine swapped, the week advanced — cannot reach this row, which is `TR-15.3`'s posture
    /// applied to the plan rather than to the targets: what a session was is a fact about the day it
    /// happened, not a view of the program as it stands now.
    public let weekNumber: Int?

    /// The ``ProgramDay/order`` this session was started from. See ``weekNumber``.
    public let dayIndex: Int?

    /// Creates a session record. No property is validated; see this module's header.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        date: Date,
        startedAt: Date?,
        endedAt: Date?,
        notes: String,
        bodyweight: Weight?,
        programRunID: UUID?,
        scheduledWorkoutID: UUID?,
        weekNumber: Int? = nil,
        dayIndex: Int? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.date = date
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
        self.bodyweight = bodyweight
        self.programRunID = programRunID
        self.scheduledWorkoutID = scheduledWorkoutID
        self.weekNumber = weekNumber
        self.dayIndex = dayIndex
    }
}

// MARK: - Codable

extension WorkoutSession {
    /// The wire format's keys, in the order they are written. See `RecordCoding.swift`.
    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case deletedAt
        case date
        case startedAt
        case endedAt
        case notes
        case bodyweight
        case programRunID
        case scheduledWorkoutID
        case weekNumber
        case dayIndex
    }

    /// Decodes the keyed shape on ``CodingKeys``. Nothing is validated.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt),
            date: try container.decode(Date.self, forKey: .date),
            startedAt: try container.decodeIfPresent(Date.self, forKey: .startedAt),
            endedAt: try container.decodeIfPresent(Date.self, forKey: .endedAt),
            notes: try container.decode(String.self, forKey: .notes),
            bodyweight: try container.decodeIfPresent(Weight.self, forKey: .bodyweight),
            programRunID: try container.decodeIfPresent(UUID.self, forKey: .programRunID),
            scheduledWorkoutID: try container.decodeIfPresent(
                UUID.self, forKey: .scheduledWorkoutID),
            weekNumber: try container.decodeIfPresent(Int.self, forKey: .weekNumber),
            dayIndex: try container.decodeIfPresent(Int.self, forKey: .dayIndex)
        )
    }

    /// Writes the thirteen keys in declaration order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(bodyweight, forKey: .bodyweight)
        try container.encodeIfPresent(programRunID, forKey: .programRunID)
        try container.encodeIfPresent(scheduledWorkoutID, forKey: .scheduledWorkoutID)
        try container.encodeIfPresent(weekNumber, forKey: .weekNumber)
        try container.encodeIfPresent(dayIndex, forKey: .dayIndex)
    }
}

/// Which week and day of a program a session was started from (`FR-16.8.3`).
///
/// **The day is counted from one**, unlike ``ProgramDay/order``, which is the cursor's own unit: a
/// lifter reads "Day 2" and a `nextDayIndex` reads 1, and the conversion has one home rather than
/// one per screen that draws it.
public struct ProgramPosition: Equatable, Sendable {
    /// The week the run was on when the workout was started.
    public let week: Int

    /// Which day of that week it was, counted from one.
    public let day: Int

    /// Builds the position.
    ///
    /// - Parameters:
    ///   - week: The run's week number.
    ///   - day: The day, counted from one.
    public init(week: Int, day: Int) {
        self.week = week
        self.day = day
    }
}

extension WorkoutSession {
    /// Where in a program this session was started, or `nil` where it was not started from one.
    ///
    /// **Both columns or neither.** They are written together at start, and a row carrying one
    /// without the other describes a position nothing can be drawn from — so a half-filled row
    /// reads here as no position at all rather than as a week with an invented day.
    public var programPosition: ProgramPosition? {
        guard let weekNumber, let dayIndex else { return nil }
        return ProgramPosition(week: weekNumber, day: dayIndex + 1)
    }
}

/// What an unfinished workout is, where a screen has to name it (`FR-16.4.3`).
///
/// **Three cases rather than a Boolean beside a date**, because the two unfinished ones are read
/// differently by the lifter and are the only thing standing where a finished session shows its
/// numbers: a workout being logged has a running total, and one dated ahead has nothing yet.
public enum SessionLifecycle: Equatable, Sendable {
    /// The workout has ended.
    case finished

    /// It is open, and its training day has arrived.
    case inProgress

    /// It is open and dated ahead of today.
    case planned
}

extension WorkoutSession {
    /// Whether the workout has ended (`FR-1.2.11`).
    ///
    /// **The one predicate `FR-16.4.2` is written in terms of**, and the reason it is here rather
    /// than spelled out at each reader: exercise history, the record calculator's input and the
    /// e1RM window are one read apiece and all three exclude an open session's sets, so "open" has
    /// to mean one thing. A set inside an open session that is not completed is *pending* rather
    /// than failed (`FR-16.4.1`) — that distinction is drawn from this and the set's own column
    /// together, never from the column alone.
    public var isFinished: Bool { endedAt != nil }

    /// Whether `set`, logged against this session, is one nobody has attempted yet (`FR-16.4.1`).
    ///
    /// **The one predicate `FR-16.4.2` is written in terms of**, and the reason it is here rather
    /// than spelled out at each reader: exercise history, the record calculator's input and the
    /// e1RM window are one read apiece, and a set that has not happened yet belongs in none of
    /// them. Two columns and no third: `isCompleted` is schema-v1 and cannot be backfilled
    /// (`G-1.8`), so a finished session stays two-valued and the same row read after Finish is a
    /// failed set.
    ///
    /// **A *completed* set inside an open session is not pending and is not excluded.** It is work
    /// that was performed, and `FR-1.6.3` badges it at the moment it is logged — which is inside
    /// the workout that logged it.
    ///
    /// - Parameter set: A set belonging to this session.
    /// - Returns: Whether it is pending.
    public func isPending(_ set: SetEntry) -> Bool {
        !isFinished && !set.isCompleted
    }

    /// Which of ``SessionLifecycle``'s three this session is on a given day.
    ///
    /// **The day rather than the instant.** `date` is the training day (`FR-1.2.1` backdates), so a
    /// workout dated today at midnight is in progress all day rather than planned until the clock
    /// passes its timestamp.
    ///
    /// - Parameters:
    ///   - today: The day to read it against.
    ///   - calendar: The calendar the two days are compared in.
    /// - Returns: What the session is.
    public func lifecycle(on today: Date, calendar: Calendar) -> SessionLifecycle {
        guard !isFinished else { return .finished }
        return calendar.startOfDay(for: date) > calendar.startOfDay(for: today)
            ? .planned : .inProgress
    }

    /// Whether the workout is open and its training day is behind us (`FR-16.4.4`).
    ///
    /// **What a way out of an open session is offered for.** A workout started today is finished
    /// where it is being logged; one left open since yesterday — imported, or abandoned — is
    /// reachable only from the history it sits in, and would otherwise stay open forever.
    ///
    /// - Parameters:
    ///   - today: The day to read it against.
    ///   - calendar: The calendar the two days are compared in.
    /// - Returns: Whether it is one of those.
    public func isStale(on today: Date, calendar: Calendar) -> Bool {
        !isFinished && calendar.startOfDay(for: date) < calendar.startOfDay(for: today)
    }
}
