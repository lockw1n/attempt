import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// `NFR-1.2` — the tap that logs a set does not wait for the record walk behind it.
///
/// **The requirement is "from tapping add set to the row appearing", and the walk is not the row.**
/// It used to be inside that span: every set writer `await`ed the recompute and then re-read the
/// list. Measured on a three-year store, 147 ms of a 221 ms tap was the walk — `NFR-1.6`'s own
/// budget, five times larger than this one, being spent inside it.
///
/// **Gated rather than timed, because a timing assertion here would prove nothing.** Over the fakes
/// both figures are microseconds; what a clock could not tell apart, a walk that cannot finish until
/// the test lets it can. The gate is on the cache *write*, which is the last thing a walk does and
/// the one thing the command path never touches — see ``warmed()`` for why the cache has to be
/// warm before the gate goes on.
@MainActor
@Suite("The answer does not await the walk")
struct AnswerDoesNotAwaitTheWalkTests {
    /// **Bounded, because the defect this catches is a hang rather than a wrong answer.** A command
    /// that went back to `await`ing the recompute cannot return while the gate below holds the walk,
    /// so the test would stop rather than fail — and neither Swift Testing nor `swift test` bounds a
    /// test on its own, which would leave `NFR-1.2`'s only guard hanging CI instead of reporting it.
    @Test(
        "The row appears while the walk is still running, and the badge follows it",
        .timeLimit(.minutes(1)))
    func theRowDoesNotWaitForTheRecompute() async throws {
        let warm = try await warmed()
        let (store, entryID, gate) = (warm.store, warm.entryID, warm.gate)
        await gate.close()

        // The heavier set takes the record off the first one, so the badge below is a claim about
        // this set rather than about whichever set happened to hold one already.
        await store.addSet(
            toEntryID: entryID,
            values: SetEntryValues(
                weight: Weight(grams: 120_000), reps: 5, rpe: nil, isWarmup: false))

        // The command has returned with the walk still blocked: the row is on the card…
        let heavier = try #require(sets(store, entryID).last)
        #expect(heavier.weight == Weight(grams: 120_000))
        #expect(store.exercises.first?.sets.count == 2)
        // …and its badge is not, because the cache still holds the answer from before it.
        #expect(store.personalRecords.marks(forSetID: heavier.id).isEmpty)

        await gate.open()
        await store.settleRecordRefresh()

        #expect(!store.personalRecords.marks(forSetID: heavier.id).isEmpty)
    }

    /// **What ``ActiveSessionStore/settleRecordRefresh()`` is worth as a settle point.** It waits on
    /// the last refresh only, so it is a complete wait exactly while each refresh waits on the one
    /// before it — and ~15 assertions across `PersonalRecordBadgeTests`, `RecordTriggerTests` and
    /// `DayCommandTests` now take their reading from it.
    ///
    /// **Deterministic in the direction that matters.** With the chain in place the second walk
    /// *cannot* reach the gate while the first is parked there, however long the test waits, so the
    /// passing run has no race in it. The yields are what give an unchained implementation — where
    /// both walks are free to run at once — every chance to show its second arrival.
    @Test("A second tap's walk waits for the first one's", .timeLimit(.minutes(1)))
    func theSecondWalkWaitsForTheFirst() async throws {
        let warm = try await warmed()
        let (store, entryID, gate) = (warm.store, warm.entryID, warm.gate)
        await gate.close()

        for grams in [110_000, 120_000] {
            await store.addSet(
                toEntryID: entryID,
                values: SetEntryValues(
                    weight: Weight(grams: grams), reps: 5, rpe: nil, isWarmup: false))
        }

        await gate.awaitArrivals(1)
        for _ in 0..<50 { await Task.yield() }
        #expect(await gate.arrivals == 1)

        await gate.open()
        await store.settleRecordRefresh()

        // Both walks have run by the time the settle point returns, and the heavier of the two taps
        // is the one holding the record — which is the order they were made in.
        #expect(await gate.arrivals == 2)
        let heaviest = try #require(sets(store, entryID).last)
        #expect(heaviest.weight == Weight(grams: 120_000))
        #expect(!store.personalRecords.marks(forSetID: heaviest.id).isEmpty)
    }

    /// A store holding one logged set with its records already computed, and the gate that stops the
    /// next walk from finishing.
    ///
    /// **Warm before the gate, and that is the read path rather than a convenience.** A cache miss is
    /// answered by walking and *writing*, so a gate closed over a cold cache would block
    /// `loadExercises()` itself — which is the command, not the chain behind it, and would make the
    /// test assert the opposite of what it claims.
    private func warmed() async throws -> Warmed {
        let stack = InMemoryRepositoryStack()
        let squat = try #require(try await Workout.seed(into: stack).first)
        let gate = RecordCacheGate(wrapped: stack.personalRecords)
        let store = ActiveSessionStore(
            repository: stack.workouts,
            catalogue: stack.exercises,
            settings: stack.settings,
            records: PersonalRecordRecomputer(workouts: stack.workouts, cache: gate),
            trainingMaxes: stack.trainingMaxes,
            programs: stack.programs)
        await store.start(on: .now)
        await store.loadExercises()
        await store.addExercise(id: squat.id)
        let entryID = try #require(store.exercises.first).id
        await store.addSet(
            toEntryID: entryID,
            values: SetEntryValues(
                weight: Weight(grams: 100_000), reps: 5, rpe: nil, isWarmup: false))
        await store.settleRecordRefresh()
        return Warmed(store: store, entryID: entryID, gate: gate)
    }

    /// The store, the exercise being logged against, and the valve on the next walk.
    private struct Warmed {
        let store: ActiveSessionStore
        let entryID: UUID
        let gate: RecordCacheGate
    }

    /// The entry's sets as the card holds them, in order.
    private func sets(_ store: ActiveSessionStore, _ entryID: UUID) -> [SetEntry] {
        store.exercises.first { $0.id == entryID }?.sets.sorted { $0.order < $1.order } ?? []
    }
}

/// The record cache with a stop valve on its one write.
///
/// **The write rather than the read**, because a read is what both the walk *and* the badge do and a
/// gate on it could not tell the command from the chain behind it.
actor RecordCacheGate: PersonalRecordCacheRepository {
    private let wrapped: any PersonalRecordCacheRepository

    /// Everyone waiting to write, in the order they arrived.
    ///
    /// **A queue rather than one slot**, because a second write reaching a closed gate would
    /// otherwise displace the first and strand its continuation — a hang, in the fixture written to
    /// prove there is no hang.
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Whether a write has to wait to be let through.
    private var isClosed = false

    /// How many writes have reached the gate since it was closed.
    ///
    /// The count is what says how many walks are in flight at once, which is the only thing about
    /// ``ActiveSessionStore/announceSetChange(inEntryID:)``'s chain a fake can observe.
    private(set) var arrivals = 0

    /// Whoever is waiting for the count to reach a threshold, and what that threshold is.
    private var watcher: (threshold: Int, continuation: CheckedContinuation<Void, Never>)?

    init(wrapped: any PersonalRecordCacheRepository) {
        self.wrapped = wrapped
    }

    /// Makes every write from here on wait, and restarts the arrival count.
    func close() {
        isClosed = true
        arrivals = 0
    }

    /// Lets every waiting write through, and every later one.
    func open() {
        isClosed = false
        for continuation in waiting { continuation.resume() }
        waiting = []
    }

    /// Waits until `count` writes have reached the gate.
    ///
    /// A settle point rather than a sleep: a test that polled would be asserting on how fast the
    /// machine happened to be.
    func awaitArrivals(_ count: Int) async {
        guard arrivals < count else { return }
        await withCheckedContinuation { watcher = (count, $0) }
    }

    /// Records a write reaching the gate, and wakes anyone waiting for it.
    private func recordArrival() {
        arrivals += 1
        if let watcher, arrivals >= watcher.threshold {
            self.watcher = nil
            watcher.continuation.resume()
        }
    }

    func personalRecords(
        forExerciseID exerciseID: UUID, includingDeleted: Bool
    ) async throws -> [PersonalRecordCache] {
        try await wrapped.personalRecords(
            forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }

    func personalRecords(includingDeleted: Bool) async throws -> [PersonalRecordCache] {
        try await wrapped.personalRecords(includingDeleted: includingDeleted)
    }

    func replacePersonalRecords(
        forExerciseID exerciseID: UUID, with values: [PersonalRecordCacheValues]
    ) async throws {
        recordArrival()
        if isClosed {
            await withCheckedContinuation { waiting.append($0) }
        }
        try await wrapped.replacePersonalRecords(forExerciseID: exerciseID, with: values)
    }
}
