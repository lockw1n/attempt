import Foundation
import PowerliftingCore
import RepositoryInterface

/// An ``ExerciseRepository`` that returns what a test hands it, counts its reads and can be made
/// to fail — the same shape as `Settings`' `ScriptedSettingsRepository`, and for the same reason:
/// the in-memory fake cannot be made to throw, and a failed read is one of this screen's four
/// states.
///
/// It returns the rows **unsorted and unfiltered**, so the ordering and the archive exclusion the
/// tests assert are the state's own and not the fake's.
///
/// A file of its own rather than the tail of ``ExerciseListStateTests``, which had reached
/// SwiftLint's length ceiling — and seven suites in this target read through it, so the file it
/// happened to be declared in was never the one it belonged to.
actor ScriptedExerciseRepository: ExerciseRepository {
    private var rows: [Exercise]
    private var readError: RepositoryError?
    private var writeError: RepositoryError?

    /// A read failure armed for later. See ``failReads(_:afterNext:)``.
    private var deferredReadFailure: (remaining: Int, error: RepositoryError)?

    /// How many reads the state made — the anchor under "a loaded catalogue is not read again".
    private(set) var reads = 0

    /// The `includingDeleted:` argument of each read, in order. A screen that asked for deleted rows
    /// would be a screen showing what `G-1.3` soft-deleted.
    private(set) var readsIncludingDeleted: [Bool] = []

    /// Every record handed to ``save(_:)``, in order — the anchor under the detail screen's write
    /// assertions, and what notices a save that never happened. The whole record rather than its
    /// notes, so a write that quietly altered another field is visible here.
    private(set) var savedRecords: [Exercise] = []

    /// Just the notes of those records, for the assertions that only care about the text.
    var savedNotes: [String] { savedRecords.map(\.notes) }

    /// Every record ``save(_:)`` was *asked* to store, landed or not.
    ///
    /// Distinct from ``savedRecords``, which holds the writes that succeeded: a retry after a failed
    /// write is invisible there, and whether the retry named the same row as the attempt before it
    /// is exactly what the create form has to get right.
    private(set) var attemptedRecords: [Exercise] = []

    /// Writes that have reached the store and are waiting to be let through. See ``holdWrites()``.
    private var heldWrites: [CheckedContinuation<Void, Never>] = []

    private var holdsWrites = false

    /// How many writes are waiting in the hold — what a test spins on to know that a command it
    /// issued has actually reached the store, rather than hoping it has.
    var writesWaiting: Int { heldWrites.count }

    init(
        exercises: [Exercise],
        readError: RepositoryError? = nil,
        writeError: RepositoryError? = nil
    ) {
        self.rows = exercises
        self.readError = readError
        self.writeError = writeError
    }

    /// Stops failing, so the next read behaves.
    func recover() { readError = nil }

    /// Stops failing writes, so the next save lands.
    func recoverWrites() { writeError = nil }

    /// Starts failing reads, so a test can break the re-read a write does without breaking the
    /// write itself — the only way to reach the "stored, but the screen could not read it back"
    /// case from outside.
    func failReads(_ error: RepositoryError) { readError = error }

    /// Starts failing reads only once `count` more of them have answered.
    ///
    /// **``failReads(_:)`` alone can no longer reach the re-read.** The detail screen's writes read
    /// the stored row *before* they write it — that row has a second writer, and a record rebuilt
    /// from the screen's own copy would clear a column the screen never shows — so a repository
    /// failing every read from now on fails the write itself and never gets as far as the read this
    /// is for. Counting past it is what keeps "stored, but the screen could not read it back"
    /// expressible.
    ///
    /// - Parameters:
    ///   - error: What the reads past the countdown throw.
    ///   - count: How many further reads answer normally first.
    func failReads(_ error: RepositoryError, afterNext count: Int) {
        deferredReadFailure = (remaining: count, error: error)
    }

    /// Holds every write *at the store* until ``releaseWrites()``.
    ///
    /// **This is what makes "a second command issued while the first is in flight" a fact rather
    /// than a race.** Two commands started as sibling child tasks run in whichever order the
    /// scheduler picks, so a test written that way asserts the interleaving it wanted only half the
    /// time — measured, and it is why this exists.
    func holdWrites() { holdsWrites = true }

    /// Lets every held write through and stops holding.
    func releaseWrites() {
        holdsWrites = false
        let waiting = heldWrites
        heldWrites = []
        for continuation in waiting { continuation.resume() }
    }

    func exercises(includingDeleted: Bool) async throws -> [Exercise] {
        try recordRead(includingDeleted)
        return rows
    }

    func exercise(id: UUID, includingDeleted: Bool) async throws -> Exercise? {
        try recordRead(includingDeleted)
        return rows.first { $0.id == id && (includingDeleted || $0.deletedAt == nil) }
    }

    /// Counts one read, arms a deferred failure when its countdown runs out, and throws whatever is
    /// in force.
    private func recordRead(_ includingDeleted: Bool) throws {
        reads += 1
        readsIncludingDeleted.append(includingDeleted)
        if let deferred = deferredReadFailure {
            if deferred.remaining <= 0 {
                readError = deferred.error
                deferredReadFailure = nil
            } else {
                deferredReadFailure = (remaining: deferred.remaining - 1, error: deferred.error)
            }
        }
        if let readError { throw readError }
    }

    /// Upserts on `id`, the way the real one does — so a screen that re-reads after a write sees
    /// what it wrote rather than what it started with.
    func save(_ exercise: Exercise) async throws {
        if holdsWrites {
            await withCheckedContinuation { heldWrites.append($0) }
        }
        attemptedRecords.append(exercise)
        if let writeError { throw writeError }
        savedRecords.append(exercise)
        if let index = rows.firstIndex(where: { $0.id == exercise.id }) {
            rows[index] = exercise
        } else {
            rows.append(exercise)
        }
    }

    func trainingMax(forExerciseID exerciseID: UUID, on date: Date) async throws -> TrainingMaxEntry? {
        nil
    }

    func trainingMaxHistory(
        forExerciseID exerciseID: UUID,
        includingDeleted: Bool
    ) async throws -> [TrainingMaxEntry] {
        []
    }

    func saveTrainingMax(_ entry: TrainingMaxEntry) async throws {}
}
