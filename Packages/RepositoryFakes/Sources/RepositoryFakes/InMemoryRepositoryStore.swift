import Foundation
import RepositoryInterface

/// The tables the fakes share, and the write and read rules they all obey.
///
/// **One store behind every fake, mirroring one container behind `Persistence`'s `@ModelActor`s.**
/// The checks a save performs are cross-table — an entry names a session and an exercise, a set
/// names an entry — so independent boxes of records could not implement the contract at all. The
/// fakes are facades over this, which is also what makes ``InMemoryRepositoryStack`` a stack rather
/// than a handful of unrelated objects.
///
/// **An actor rather than a lock.** The real repositories are actors over one container, and
/// `Persistence` needed a process-wide lock on top of that for the settings singleton — an actor
/// serialises its own calls and nothing else. Here there is one actor for all of them, so the
/// singleton is safe by construction rather than by a second mechanism.
///
/// The tables are keyed by `id`, which is what makes a duplicate-`id` pair unrepresentable here;
/// this module's header has the argument.
actor InMemoryRepositoryStore {
    // Not `private`: each repository's rules live in an extension in its own file, which is the
    // same split `Persistence` uses, and `private` is file-scoped.
    var exercises: [UUID: Exercise] = [:]
    var trainingMaxes: [UUID: TrainingMaxEntry] = [:]
    var sessions: [UUID: WorkoutSession] = [:]
    var entries: [UUID: ExerciseEntry] = [:]
    var sets: [UUID: SetEntry] = [:]
    var bodyweightEntries: [UUID: BodyweightEntry] = [:]
    var profiles: [UUID: EquipmentProfile] = [:]
    var personalRecordCache: [UUID: PersonalRecordCache] = [:]
    var settingsRow: UserSettings?
    var routines: [UUID: Routine] = [:]
    var routineExercises: [UUID: RoutineExercise] = [:]
    var routineTargetGroups: [UUID: RoutineTargetGroup] = [:]

    /// An empty store.
    init() {}

    // MARK: - Writing

    /// Inserts `record`, or overwrites the row already carrying its id, applying rule 7.
    ///
    /// The fakes' whole implementation of "the audit columns belong to the write path": `updatedAt`
    /// becomes `now` whatever the record said, `deletedAt` keeps whatever the stored row holds — so
    /// a save neither deletes nor resurrects — and `createdAt` is the record's only when the row is
    /// new, which is what lets a restore keep the history it arrived with (`FR-1.11.3`).
    func upserted<Record: AuditStamped>(
        _ record: Record,
        into table: inout [UUID: Record],
        at now: Date
    ) {
        let existing = table[record.id]
        table[record.id] = record.stamped(
            createdAt: existing?.createdAt ?? record.createdAt,
            updatedAt: now,
            deletedAt: existing?.deletedAt
        )
    }

    /// Soft-deletes the live row carrying `id` (`G-1.3`).
    ///
    /// **A row that is already deleted is not there to delete**, so this raises `recordNotFound`
    /// rather than restamping it — the real implementations fetch live rows and refuse an empty
    /// match set, and re-deleting would move `updatedAt` on a row nothing reads.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/recordNotFound(id:)`` when no live row
    ///   carries `id`.
    func softDelete<Record: AuditStamped>(
        id: UUID,
        in table: inout [UUID: Record],
        at now: Date
    ) throws {
        guard let row = table[id], !row.isSoftDeleted else {
            throw RepositoryError.recordNotFound(id: id)
        }
        table[id] = row.stamped(createdAt: row.createdAt, updatedAt: now, deletedAt: now)
    }

    /// Soft-deletes `row` if it is live, and leaves it alone if it is not.
    ///
    /// The cascade's shape rather than a delete's: an entry that was already deleted keeps both the
    /// date it left the user's history and the `updatedAt` it had, because re-stamping it would
    /// relabel a write that did not happen — and `updatedAt` is `G-2.4`'s conflict key.
    func sweeping<Record: AuditStamped>(_ row: Record, at now: Date) -> Record {
        guard !row.isSoftDeleted else { return row }
        return row.stamped(createdAt: row.createdAt, updatedAt: now, deletedAt: now)
    }

    /// Whether any row carries `id`, soft-deleted rows included.
    ///
    /// **A soft-deleted target is not a dangling reference.** The question a join key asks is
    /// whether the row exists; requiring a *live* one would make re-saving a set inside a deleted
    /// session throw `danglingReference`, which names a different fault.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/danglingReference(recordID:referencing:)``
    ///   when no row carries `id`.
    func requireReferenced<Record: StoredRecord>(
        _ table: [UUID: Record],
        id: UUID,
        from recordID: UUID
    ) throws {
        guard table[id] != nil else {
            throw RepositoryError.danglingReference(recordID: recordID, referencing: id)
        }
    }
}

// MARK: - Reading

extension Sequence where Element: StoredRecord {
    /// The rows a read may return, by rule 1 of the `RepositoryInterface` header.
    func live(includingDeleted: Bool) -> [Element] {
        includingDeleted ? Array(self) : filter { !$0.isSoftDeleted }
    }
}

extension Sequence {
    /// `self` ordered by a key ending in `id.uuidString`, and therefore deterministically.
    ///
    /// **Written here rather than shared with `Persistence`, on purpose.** Every list either
    /// implementation returns goes through its own copy of this: a conformance suite whose two
    /// subjects sort with the same function can only prove that the function runs. A dictionary's
    /// values additionally have no order at all and Swift's hash seed changes per process, so on
    /// this side the alternative is not "an arbitrary but stable answer" but a different answer
    /// every launch.
    ///
    /// Two overloads rather than one generic over `Key: Comparable`, because a tuple is not
    /// `Comparable` — the stdlib publishes `<` for tuples as free operators and no conformance.
    /// Both evaluate `key` once per element.
    func sortedDeterministically<A: Comparable, B: Comparable>(
        by key: (Element) -> (A, B),
        descending: Bool = false
    ) -> [Element] {
        map { (key: key($0), element: $0) }
            .sorted { descending ? $0.key > $1.key : $0.key < $1.key }
            .map(\.element)
    }

    /// The form for a key with more members than a tuple may carry here.
    ///
    /// No `descending:` on this one: the only caller is the personal-record feed, which is oldest
    /// first by definition, and a parameter nothing passes is a branch no test can reach.
    func sortedDeterministically<Key: Comparable>(by key: (Element) -> Key) -> [Element] {
        map { (key: key($0), element: $0) }
            .sorted { $0.key < $1.key }
            .map(\.element)
    }
}
