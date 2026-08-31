import Foundation
import RepositoryInterface

/// Where an entry sits in the timeline — the two halves of the feed's order that live on other rows.
///
/// A second implementation of `Persistence`'s `FeedPosition`, not a shared one: see the note on
/// `Sequence.sortedDeterministically(by:descending:)`.
struct FeedPosition: Comparable {
    let sessionDate: Date
    let entryOrder: Int

    /// The position of an entry whose session row is not there. Last, not first.
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

/// `WorkoutRepository` over dictionaries (`TR-0.4.2`).
///
/// The three levels join by `UUID` here exactly as they do in the store, so the cascade and the
/// personal-record ordering are written rather than inherited.
struct InMemoryWorkoutRepository: WorkoutRepository, Sendable {
    let store: InMemoryRepositoryStore

    /// Sessions dated within `range`, newest first.
    func sessions(
        in range: ClosedRange<Date>,
        includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        await store.allSessions(in: range, includingDeleted: includingDeleted)
    }

    /// The session carrying `id`, or `nil`.
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        await store.session(id: id, includingDeleted: includingDeleted)
    }

    /// Inserts or replaces the session. `programRunID` and `scheduledWorkoutID` are unchecked —
    /// the entities they name are Phase 2's.
    func save(_ session: WorkoutSession) async throws {
        await store.saveSession(session)
    }

    /// Soft-deletes the session, its entries and their sets, in one write.
    func deleteSession(id: UUID) async throws {
        try await store.deleteSession(id: id)
    }

    /// The session's entries, by order then id.
    func entries(
        forSessionID sessionID: UUID,
        includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        await store.allEntries(forSessionID: sessionID, includingDeleted: includingDeleted)
    }

    /// The entry carrying `id`, or `nil`.
    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? {
        await store.entry(id: id, includingDeleted: includingDeleted)
    }

    /// Inserts or replaces the entry, refusing a session or exercise that does not exist.
    func save(_ entry: ExerciseEntry) async throws {
        try await store.saveEntry(entry)
    }

    /// Soft-deletes the entry and its sets.
    func deleteExerciseEntry(id: UUID) async throws {
        try await store.deleteExerciseEntry(id: id)
    }

    /// The entry's sets, by order then id.
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        await store.allSets(forEntryID: entryID, includingDeleted: includingDeleted)
    }

    /// Inserts or replaces the set, refusing an entry that does not exist. `modifiers` are
    /// canonicalised on the way in.
    func save(_ set: SetEntry) async throws {
        try await store.saveSet(set)
    }

    /// Soft-deletes the set. Nothing else moves.
    func deleteSet(id: UUID) async throws {
        try await store.deleteSet(id: id)
    }

    /// Every set logged against one exercise, oldest first, on the four-key order `TR-0.2.8`
    /// depends on. Warmups and incomplete sets are included.
    func sets(
        forExerciseID exerciseID: UUID,
        includingDeleted: Bool
    ) async throws -> [SetEntry] {
        await store.allSets(forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }
}

extension InMemoryRepositoryStore {
    /// Sessions dated within `range`, newest first.
    func allSessions(in range: ClosedRange<Date>, includingDeleted: Bool) -> [WorkoutSession] {
        sessions.values
            .filter { range.contains($0.date) }
            .live(includingDeleted: includingDeleted)
            .sortedDeterministically(by: { ($0.date, $0.id.uuidString) }, descending: true)
    }

    /// The session carrying `id`, subject to the flag.
    func session(id: UUID, includingDeleted: Bool) -> WorkoutSession? {
        sessions[id].flatMap { includingDeleted || !$0.isSoftDeleted ? $0 : nil }
    }

    /// Inserts or replaces `session`.
    func saveSession(_ session: WorkoutSession) {
        upserted(session, into: &sessions, at: .now)
    }

    /// Soft-deletes the session and everything under it, in one write.
    ///
    /// **The entries swept include already-deleted ones — for their *sets*, not for themselves.** An
    /// entry deleted on its own leaves no live set behind, but a foreign row can arrive in that
    /// state, and rule 3's promise is that a deleted session leaves no live set anywhere under it.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/recordNotFound(id:)`` when no live session
    ///   carries `id`.
    func deleteSession(id: UUID) throws {
        let now = Date.now
        try softDelete(id: id, in: &sessions, at: now)
        cascade(intoEntryIDs: entries.values.filter { $0.sessionID == id }.map(\.id), at: now)
    }

    /// The session's entries, by order then id.
    func allEntries(forSessionID sessionID: UUID, includingDeleted: Bool) -> [ExerciseEntry] {
        entries.values
            .filter { $0.sessionID == sessionID }
            .live(includingDeleted: includingDeleted)
            .sortedDeterministically { ($0.order, $0.id.uuidString) }
    }

    /// The entry carrying `id`, subject to the flag.
    func entry(id: UUID, includingDeleted: Bool) -> ExerciseEntry? {
        entries[id].flatMap { includingDeleted || !$0.isSoftDeleted ? $0 : nil }
    }

    /// Inserts or replaces `entry`, checking both of its join keys.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/danglingReference(recordID:referencing:)``
    ///   when either names no row.
    func saveEntry(_ entry: ExerciseEntry) throws {
        try requireReferenced(sessions, id: entry.sessionID, from: entry.id)
        try requireReferenced(exercises, id: entry.exerciseID, from: entry.id)
        upserted(entry, into: &entries, at: .now)
    }

    /// Soft-deletes the entry and its sets.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/recordNotFound(id:)`` when no live entry
    ///   carries `id`.
    func deleteExerciseEntry(id: UUID) throws {
        let now = Date.now
        guard let entry = entries[id], !entry.isSoftDeleted else {
            throw RepositoryError.recordNotFound(id: id)
        }
        cascade(intoEntryIDs: [id], at: now)
    }

    /// The entry's sets, by order then id.
    func allSets(forEntryID entryID: UUID, includingDeleted: Bool) -> [SetEntry] {
        sets.values
            .filter { $0.entryID == entryID }
            .live(includingDeleted: includingDeleted)
            .sortedDeterministically { ($0.order, $0.id.uuidString) }
    }

    /// Inserts or replaces `set`, canonicalising its modifiers.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/danglingReference(recordID:referencing:)``
    ///   when `entryID` names no row.
    func saveSet(_ set: SetEntry) throws {
        try requireReferenced(entries, id: set.entryID, from: set.id)
        upserted(set.canonicalisingModifiers(), into: &sets, at: .now)
    }

    /// Soft-deletes the set.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/recordNotFound(id:)`` when no live set
    ///   carries `id`.
    func deleteSet(id: UUID) throws {
        try softDelete(id: id, in: &sets, at: .now)
    }

    /// Every set logged against one exercise, in the order `PersonalRecordCalculator` is handed.
    ///
    /// **The session lookup always includes deleted sessions.** A session is read for its date
    /// rather than for itself, and a live entry can belong to a deleted one, so filtering there
    /// would cost the *ordering* of a set the caller did ask for.
    ///
    /// **The key ends in the set's id, which is stronger than "stably".** A stable sort preserves
    /// the input order among equal keys, and the input here is a dictionary's values; `order` is not
    /// unique, so without the fourth clause `TR-0.2.8`'s tie-break would move between launches,
    /// silently, and only between sets that weigh the same.
    func allSets(forExerciseID exerciseID: UUID, includingDeleted: Bool) -> [SetEntry] {
        let matching = entries.values
            .filter { $0.exerciseID == exerciseID }
            .live(includingDeleted: includingDeleted)

        // No early return for an empty match set. `Persistence` has one because it saves two
        // fetches; here it would only be an unreachable branch — an empty `orderingKey` already
        // admits no sets — and a probe confirmed no test can turn it red.
        var orderingKey: [UUID: FeedPosition] = [:]
        for entry in matching {
            orderingKey[entry.id] = FeedPosition(
                sessionDate: sessions[entry.sessionID]?.date ?? .distantFuture,
                entryOrder: entry.order
            )
        }

        return sets.values
            .filter { orderingKey[$0.entryID] != nil }
            .live(includingDeleted: includingDeleted)
            .sortedDeterministically { set in
                // Unreachable, and an expression rather than a `!`: the filter above admitted only
                // sets whose entry is in `orderingKey`. Same verdict the store side reached about
                // the same `??`.
                let position = orderingKey[set.entryID] ?? .unplaced
                return FeedSortKey(
                    position: position, setOrder: set.order, setID: set.id.uuidString)
            }
    }

    /// Soft-deletes the named entries and every live set hanging off them, without a save of its
    /// own.
    ///
    /// Shared by the two cascading deletes so that "a deleted entry never leaves a live set" is one
    /// piece of code rather than an obligation on two. An entry already deleted keeps the date it
    /// left the user's history *and* its `updatedAt`, while its live sets are swept like any other.
    private func cascade(intoEntryIDs entryIDs: [UUID], at now: Date) {
        for id in entryIDs {
            guard let entry = entries[id] else { continue }
            entries[id] = sweeping(entry, at: now)
        }

        let swept = Set(entryIDs)
        for (id, set) in sets where swept.contains(set.entryID) {
            sets[id] = sweeping(set, at: now)
        }
    }
}
