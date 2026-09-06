import Foundation
import RepositoryInterface
import SwiftData

/// Where an entry sits in the timeline — the two halves of the feed's order that live on other
/// rows.
///
/// A struct rather than a tuple because the whole key has four members and the lint ceiling for a
/// tuple is two; naming the halves is the better shape anyway, since `date` alone does not say
/// whose date it is.
struct FeedPosition: Comparable {
    let sessionDate: Date
    let sessionStart: Date
    let entryOrder: Int

    /// The position of an entry whose session row is not there. Last, not first — see
    /// ``SwiftDataWorkoutRepository/sets(forExerciseID:includingDeleted:)``.
    ///
    /// **It keeps the entry's own order.** The session is what is missing, not the entry, and two
    /// entries of one absent session still happened in a known order; collapsing them onto a single
    /// position would sort a foreign session's sets by set order across its entries, which is an
    /// answer nothing measured.
    ///
    /// **Unreachable through the repository API, and kept correct anyway.** `save(_:)` refuses an
    /// entry whose `sessionID` names no session (`danglingReference`) and the session lookup above
    /// includes deleted rows, so nothing this app writes can land here — only a row it did not,
    /// which is what the branch exists for, so no test can turn it red.
    ///
    /// - Parameter entryOrder: The entry's position within the session that is not there.
    /// - Returns: The position.
    static func unplaced(entryOrder: Int) -> FeedPosition {
        FeedPosition(
            sessionDate: .distantFuture, sessionStart: .distantFuture, entryOrder: entryOrder)
    }

    static func < (lhs: FeedPosition, rhs: FeedPosition) -> Bool {
        (lhs.sessionDate, lhs.sessionStart, lhs.entryOrder)
            < (rhs.sessionDate, rhs.sessionStart, rhs.entryOrder)
    }
}

extension FeedPosition {
    /// Where a session sits, with its day first and the instant it was started second.
    ///
    /// **A session never tracked live sorts earliest in its own day.** `startedAt` is the only
    /// column separating two workouts on one training day, and a row without one claims nothing
    /// about having happened after a row that has one.
    ///
    /// - Parameters:
    ///   - session: The session the entry belongs to.
    ///   - entryOrder: The entry's position within it.
    init(session: WorkoutSession, entryOrder: Int) {
        self.init(
            sessionDate: session.date,
            sessionStart: session.startedAt ?? .distantPast,
            entryOrder: entryOrder)
    }
}

/// The total order `TR-0.2.8`'s tie-break depends on: session date, session start, entry order, set
/// order, then the set's own id.
struct FeedSortKey: Comparable {
    let position: FeedPosition
    let setOrder: Int
    let setID: String

    static func < (lhs: FeedSortKey, rhs: FeedSortKey) -> Bool {
        if lhs.position != rhs.position { return lhs.position < rhs.position }
        return (lhs.setOrder, lhs.setID) < (rhs.setOrder, rhs.setID)
    }
}

/// `WorkoutRepository` over SwiftData (`TR-0.4.2`, `FR-1.2`).
///
/// Three levels joined by `UUID` columns, because `G-2.5` forbids relationships — so the cascade
/// and the personal-record ordering are both written here rather than inherited from the store.
///
/// **It answers `PlannedTargetRepository` too** (`TR-15.3`). A planned target hangs off an entry
/// like a set does, so its cascade is this type's, and splitting it across two actors over one
/// container would mean two writers for one delete.
@ModelActor
actor SwiftDataWorkoutRepository: WorkoutRepository, PlannedTargetRepository {
    func sessions(in range: ClosedRange<Date>, includingDeleted: Bool) throws -> [WorkoutSession] {
        let (start, end) = (range.lowerBound, range.upperBound)
        return try modelContext.rows(
            WorkoutSessionEntity.self,
            matching: #Predicate { $0.date >= start && $0.date <= end },
            includingDeleted: includingDeleted
        )
        .sortedDeterministically(by: { ($0.date, $0.id.uuidString) }, descending: true)
        .map(\.record)
    }

    func session(id: UUID, includingDeleted: Bool) throws -> WorkoutSession? {
        try modelContext.row(WorkoutSessionEntity.self, id: id, includingDeleted: includingDeleted)?
            .record
    }

    func save(_ session: WorkoutSession) throws {
        try modelContext.upsert(session, as: WorkoutSessionEntity.self)
        try modelContext.saveStamped()
    }

    /// Soft-deletes the session, its entries and their sets, in one write.
    ///
    /// **Every row carrying `id` is swept, not just the one a read would return.** Deleting only the
    /// tiebreak winner would leave a duplicate live and readable, so the delete would appear to do
    /// nothing the next time the loser won.
    func deleteSession(id: UUID) throws {
        let sessions = try modelContext.rows(
            WorkoutSessionEntity.self, id: id, includingDeleted: false)
        guard !sessions.isEmpty else { throw RepositoryError.recordNotFound(id: id) }

        let now = Date.now
        for session in sessions { session.markDeleted(at: now) }

        // Deleted entries are swept in too — for their *sets*, not for themselves. An entry deleted
        // on its own leaves no live set behind, but a foreign row can arrive in that state, and
        // rule 3's promise is that a deleted session leaves no live set anywhere under it.
        let entries = try modelContext.rows(
            ExerciseEntryEntity.self,
            matching: #Predicate { $0.sessionID == id },
            includingDeleted: true
        )
        try cascade(into: entries, at: now)
        try modelContext.saveStamped(at: now)
    }

    func entries(forSessionID sessionID: UUID, includingDeleted: Bool) throws -> [ExerciseEntry] {
        try modelContext.rows(
            ExerciseEntryEntity.self,
            matching: #Predicate { $0.sessionID == sessionID },
            includingDeleted: includingDeleted
        )
        .sortedDeterministically { ($0.order, $0.id.uuidString) }
        .map(\.record)
    }

    func entry(id: UUID, includingDeleted: Bool) throws -> ExerciseEntry? {
        try modelContext.row(ExerciseEntryEntity.self, id: id, includingDeleted: includingDeleted)?
            .record
    }

    func save(_ entry: ExerciseEntry) throws {
        try modelContext.requireReferenced(
            WorkoutSessionEntity.self, id: entry.sessionID, from: entry.id)
        try modelContext.requireReferenced(
            ExerciseEntity.self, id: entry.exerciseID, from: entry.id)
        try modelContext.upsert(entry, as: ExerciseEntryEntity.self)
        try modelContext.saveStamped()
    }

    func deleteExerciseEntry(id: UUID) throws {
        let entries = try modelContext.rows(
            ExerciseEntryEntity.self, id: id, includingDeleted: false)
        guard !entries.isEmpty else { throw RepositoryError.recordNotFound(id: id) }

        let now = Date.now
        try cascade(into: entries, at: now)
        try modelContext.saveStamped(at: now)
    }

    func sets(forEntryID entryID: UUID, includingDeleted: Bool) throws -> [SetEntry] {
        try modelContext.rows(
            SetEntryEntity.self,
            matching: #Predicate { $0.entryID == entryID },
            includingDeleted: includingDeleted
        )
        .sortedDeterministically { ($0.order, $0.id.uuidString) }
        .map(\.record)
    }

    func save(_ set: SetEntry) throws {
        try modelContext.requireReferenced(
            ExerciseEntryEntity.self, id: set.entryID, from: set.id)
        try modelContext.upsert(set, as: SetEntryEntity.self)
        try modelContext.saveStamped()
    }

    func deleteSet(id: UUID) throws {
        let sets = try modelContext.rows(SetEntryEntity.self, id: id, includingDeleted: false)
        guard !sets.isEmpty else { throw RepositoryError.recordNotFound(id: id) }

        let now = Date.now
        for set in sets { set.markDeleted(at: now) }
        try modelContext.saveStamped(at: now)
    }

    /// Every set logged against one exercise that somebody performed, oldest first, ordered by
    /// `(session date, session start, entry order, set order)` — the collection
    /// `PersonalRecordCalculator` is handed.
    ///
    /// **Three fetches, and the second one always includes deleted rows.** The session is read for
    /// its day, its start and whether it has ended rather than for itself, and a live entry can
    /// belong to a deleted session — a foreign row, since the cascade would otherwise have taken it
    /// — so filtering *there* would cost the ordering of a set the caller did ask for.
    ///
    /// **A pending set is dropped** (`FR-16.4.2`), and dropping is the only available shape: a set
    /// nobody has attempted, sorted late, would still be an offset a `PersonalRecord` could land on.
    /// The filter is per *set* rather than per entry, one entry being able to hold work that was
    /// performed and work that has not been.
    ///
    /// **The key ends in `id.uuidString`, which is stronger than the "stably" the protocol asks
    /// for, and deliberately.** A stable sort preserves the input order among equal keys, and the
    /// input here is an unordered fetch: stability over an arbitrary order is an arbitrary answer,
    /// which is what rule 2 refuses everywhere else in this module. Two sets can share all three
    /// stated keys — `order` is not unique — so without the fourth clause `TR-0.2.8`'s tie-break
    /// would move between runs, silently, and only between sets that weigh the same.
    ///
    /// **A set whose session row is missing sorts last, and is kept.** `SchemaDefaults.sessionDate`
    /// already made this call in the other direction for the same reason: earliest is the position
    /// that *wins* every `TR-0.2.8` tie, so a row this app did not write must not land there. It is
    /// not dropped as a pending set is: absent is not open, and a foreign row is history whose day
    /// is unknown rather than work that has not happened.
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) throws -> [SetEntry] {
        let entries = try modelContext.rows(
            ExerciseEntryEntity.self,
            matching: #Predicate { $0.exerciseID == exerciseID },
            includingDeleted: includingDeleted
        )
        guard !entries.isEmpty else { return [] }

        let sessionIDs = entries.map(\.sessionID)
        let sessions = Dictionary(
            grouping: try modelContext.rows(
                WorkoutSessionEntity.self,
                matching: #Predicate { sessionIDs.contains($0.id) },
                includingDeleted: true
            ),
            by: \.id
        ).compactMapValues { resolved($0)?.record }

        var orderingKey: [UUID: FeedPosition] = [:]
        var openSessions: [UUID: WorkoutSession] = [:]
        for (id, duplicates) in Dictionary(grouping: entries, by: \.id) {
            guard let entry = resolved(duplicates) else { continue }
            guard let session = sessions[entry.sessionID] else {
                orderingKey[id] = .unplaced(entryOrder: entry.order)
                continue
            }
            if !session.isFinished { openSessions[id] = session }
            orderingKey[id] = FeedPosition(session: session, entryOrder: entry.order)
        }

        let entryIDs = entries.map(\.id)
        return try modelContext.rows(
            SetEntryEntity.self,
            matching: #Predicate { entryIDs.contains($0.entryID) },
            includingDeleted: includingDeleted
        )
        // `FR-16.4.2`: a set nobody has attempted yet is not history. Dropped rather than sorted
        // late, which is what makes the exclusion true of the offsets a caller reads back.
        .filter { openSessions[$0.entryID]?.isPending($0.record) != true }
        .sortedDeterministically { set in
            // The `??` is unreachable and stays as an expression rather than a `!`: these sets were
            // fetched *by* the ids `orderingKey` was built from, so a miss would mean the store
            // answered a `contains` with a row outside the list. A mutation probe confirmed no test
            // can turn it red, which is the reason it is written down rather than trusted.
            let position = orderingKey[set.entryID] ?? .unplaced(entryOrder: .max)
            return FeedSortKey(position: position, setOrder: set.order, setID: set.id.uuidString)
        }
        .map(\.record)
    }

    // MARK: - Planned targets

    /// The groups planned for one entry, by order then id (`TR-15.3`).
    func plannedTargets(
        forEntryID entryID: UUID, includingDeleted: Bool
    ) throws -> [PlannedTargetGroup] {
        try modelContext.rows(
            PlannedTargetGroupEntity.self,
            matching: #Predicate { $0.exerciseEntryID == entryID },
            includingDeleted: includingDeleted
        )
        .sortedDeterministically { ($0.order, $0.id.uuidString) }
        .map(\.record)
    }

    func save(_ group: PlannedTargetGroup) throws {
        try modelContext.requireReferenced(
            ExerciseEntryEntity.self, id: group.exerciseEntryID, from: group.id)
        try modelContext.upsert(group, as: PlannedTargetGroupEntity.self)
        try modelContext.saveStamped()
    }

    /// Soft-deletes `entries`, every set hanging off them and every target planned for them,
    /// without saving.
    ///
    /// Shared by the two cascading deletes so that "a deleted entry never leaves a live set" is one
    /// piece of code rather than an obligation on two. An entry already deleted keeps the date it
    /// was deleted on — re-stamping it would relabel when it left the user's history — while its
    /// live sets are swept like any other.
    private func cascade(into entries: [ExerciseEntryEntity], at now: Date) throws {
        for entry in entries where !entry.isSoftDeleted { entry.markDeleted(at: now) }

        let entryIDs = entries.map(\.id)
        guard !entryIDs.isEmpty else { return }
        let sets = try modelContext.rows(
            SetEntryEntity.self,
            matching: #Predicate { entryIDs.contains($0.entryID) },
            includingDeleted: false
        )
        for set in sets { set.markDeleted(at: now) }

        // The plan goes with the exercise it was planned for (`TR-15.3`): a target left live under
        // a deleted entry is a prescription for work nothing can be logged against.
        let planned = try modelContext.rows(
            PlannedTargetGroupEntity.self,
            matching: #Predicate { entryIDs.contains($0.exerciseEntryID) },
            includingDeleted: false
        )
        for group in planned { group.markDeleted(at: now) }
    }
}
