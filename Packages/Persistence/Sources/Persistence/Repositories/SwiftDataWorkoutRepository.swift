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
    let entryOrder: Int

    /// The position of an entry whose session row is not there. Last, not first — see
    /// ``SwiftDataWorkoutRepository/sets(forExerciseID:includingDeleted:)``.
    static let unplaced = FeedPosition(sessionDate: .distantFuture, entryOrder: .max)

    static func < (lhs: FeedPosition, rhs: FeedPosition) -> Bool {
        (lhs.sessionDate, lhs.entryOrder) < (rhs.sessionDate, rhs.entryOrder)
    }
}

/// The total order `TR-0.2.8`'s tie-break depends on: session date, entry order, set order, then
/// the set's own id.
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
@ModelActor
actor SwiftDataWorkoutRepository: WorkoutRepository {
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

    /// Every set logged against one exercise, oldest first, ordered by
    /// `(session date, entry order, set order)` — the collection `PersonalRecordCalculator` is
    /// handed.
    ///
    /// **Three fetches, and the third one always includes deleted rows.** The session is read for
    /// its date rather than for itself, and a live entry can belong to a deleted session — a
    /// foreign row, since the cascade would otherwise have taken it — so filtering there would cost
    /// the *ordering* of a set the caller did ask for.
    ///
    /// **The key ends in `id.uuidString`, which is stronger than the "stably" the protocol asks
    /// for, and deliberately.** A stable sort preserves the input order among equal keys, and the
    /// input here is an unordered fetch: stability over an arbitrary order is an arbitrary answer,
    /// which is what rule 2 refuses everywhere else in this module. Two sets can share all three
    /// stated keys — `order` is not unique — so without the fourth clause `TR-0.2.8`'s tie-break
    /// would move between runs, silently, and only between sets that weigh the same.
    ///
    /// **A set whose session row is missing sorts last, not first.** `SchemaDefaults.sessionDate`
    /// already made this call in the other direction for the same reason: earliest is the position
    /// that *wins* every `TR-0.2.8` tie, so a row this app did not write must not land there.
    /// Dropping it is not available — that would shift every offset after it.
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) throws -> [SetEntry] {
        let entries = try modelContext.rows(
            ExerciseEntryEntity.self,
            matching: #Predicate { $0.exerciseID == exerciseID },
            includingDeleted: includingDeleted
        )
        guard !entries.isEmpty else { return [] }

        let sessionIDs = entries.map(\.sessionID)
        let sessionDates = Dictionary(
            grouping: try modelContext.rows(
                WorkoutSessionEntity.self,
                matching: #Predicate { sessionIDs.contains($0.id) },
                includingDeleted: true
            ),
            by: \.id
        ).compactMapValues { resolved($0)?.date }

        var orderingKey: [UUID: FeedPosition] = [:]
        for (id, duplicates) in Dictionary(grouping: entries, by: \.id) {
            guard let entry = resolved(duplicates) else { continue }
            orderingKey[id] = FeedPosition(
                sessionDate: sessionDates[entry.sessionID] ?? .distantFuture,
                entryOrder: entry.order
            )
        }

        let entryIDs = entries.map(\.id)
        return try modelContext.rows(
            SetEntryEntity.self,
            matching: #Predicate { entryIDs.contains($0.entryID) },
            includingDeleted: includingDeleted
        )
        .sortedDeterministically { set in
            // The `??` is unreachable and stays as an expression rather than a `!`: these sets were
            // fetched *by* the ids `orderingKey` was built from, so a miss would mean the store
            // answered a `contains` with a row outside the list. A mutation probe confirmed no test
            // can turn it red, which is the reason it is written down rather than trusted.
            let position = orderingKey[set.entryID] ?? .unplaced
            return FeedSortKey(position: position, setOrder: set.order, setID: set.id.uuidString)
        }
        .map(\.record)
    }

    /// Soft-deletes `entries` and every set hanging off them, without saving.
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
    }
}
