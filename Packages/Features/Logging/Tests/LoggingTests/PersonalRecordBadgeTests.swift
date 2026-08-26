import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-1.6.3` — the badge appears on a set the moment it is logged.
///
/// **"The same interaction" is what these are actually about, and it is a claim about the write
/// path rather than about a view.** Every command that writes a set column `await`s
/// `PersonalRecordRecomputer.setDidChange(inEntryID:)` and *then* calls `loadExercises()`, which is
/// where the marks are read; so a single `await` on the command is the whole interaction, and a mark
/// that is not there when it returns is a mark the user would have had to refresh to see.
///
/// That ordering is why nothing here is optimistic: the value read is the recomputed one, from
/// `G-1.5`'s cache, and there is no provisional mark to correct afterwards.
@MainActor
@Suite("Personal record badge")
struct PersonalRecordBadgeTests {
    /// A workout with the squat added and nothing logged against it yet.
    private func startedSquat() async throws -> (workout: Workout, entryID: UUID) {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let card = try #require(workout.store.exercises.first)
        return (workout, card.id)
    }

    /// The rep counts the store says `setID` holds the record at.
    private func marks(_ workout: Workout, _ setID: UUID) -> [Int] {
        workout.store.personalRecords.repCounts(forSetID: setID)
    }

    /// The set logged at `position` under `entryID`.
    private func loggedSet(
        _ workout: Workout, _ entryID: UUID, at position: Int
    ) async throws -> SetEntry {
        let stored = try await workout.repositories.workouts.sets(
            forEntryID: entryID, includingDeleted: false)
        return try #require(stored.sorted { $0.order < $1.order }[safe: position])
    }

    @Test("A logged set is marked without a second read")
    func aLoggedSetIsMarkedImmediately() async throws {
        let (workout, entryID) = try await startedSquat()

        await workout.store.addSet(
            toEntryID: entryID,
            values: SetEntryValues(
                weight: Weight(grams: 100_000), reps: 5, rpe: nil, isWarmup: false))

        // Nothing else is called: no reload, no navigation. The one command is the interaction.
        let logged = try await loggedSet(workout, entryID, at: 0)
        #expect(marks(workout, logged.id) == [1, 2, 3, 4, 5])
    }

    /// **The requirement's own example.** A set that beats an existing 3RM takes the badge, and the
    /// set that used to hold it loses the counts it no longer stands at — which is the half a test
    /// that only looked at the new row would miss.
    @Test("A set that beats an existing 3RM is badged, and the old holder gives it up")
    func beatingAnExistingRecordMovesTheBadge() async throws {
        let (workout, entryID) = try await startedSquat()
        await workout.store.addSet(
            toEntryID: entryID,
            values: SetEntryValues(
                weight: Weight(grams: 100_000), reps: 3, rpe: nil, isWarmup: false))
        let first = try await loggedSet(workout, entryID, at: 0)
        #expect(marks(workout, first.id) == [1, 2, 3])

        await workout.store.addSet(
            toEntryID: entryID,
            values: SetEntryValues(
                weight: Weight(grams: 110_000), reps: 3, rpe: nil, isWarmup: false))

        let heavier = try await loggedSet(workout, entryID, at: 1)
        #expect(marks(workout, heavier.id) == [1, 2, 3])
        #expect(marks(workout, first.id).isEmpty)
    }

    /// A warmup is not the work, so it holds no record — the same exclusion every derived value in
    /// this app makes, arriving here as a row with no badge.
    @Test("A warmup is not badged")
    func aWarmupIsNotBadged() async throws {
        let (workout, entryID) = try await startedSquat()

        await workout.store.addSet(
            toEntryID: entryID,
            values: SetEntryValues(
                weight: Weight(grams: 60_000), reps: 5, rpe: nil, isWarmup: true))

        let logged = try await loggedSet(workout, entryID, at: 0)
        #expect(marks(workout, logged.id).isEmpty)
        #expect(workout.store.personalRecords.bySetID.isEmpty)
    }

    /// **Marking a logged set as a warmup takes its badge away in the same interaction**, which is
    /// the read path meeting `FR-1.2.4`'s correction: the set stops being one `FR-1.6.1` counts, and
    /// the row it is drawn on is the same row.
    @Test("Marking a set as a warmup retires its badge")
    func markingAsWarmupRetiresTheBadge() async throws {
        let (workout, entryID) = try await startedSquat()
        await workout.store.addSet(
            toEntryID: entryID,
            values: SetEntryValues(
                weight: Weight(grams: 100_000), reps: 5, rpe: nil, isWarmup: false))
        let logged = try await loggedSet(workout, entryID, at: 0)
        #expect(!marks(workout, logged.id).isEmpty)

        await workout.store.markSet(id: logged.id, inEntryID: entryID, isWarmup: true)

        #expect(marks(workout, logged.id).isEmpty)
    }

    /// **Nothing has looked and nothing holds a record are the same empty dictionary**, so the flag
    /// is what separates them — the distinction `PreviousPerformances` makes on the same screen.
    @Test("A store that has not read yet reports no marks rather than an answer")
    func anUnreadStoreClaimsNothing() async throws {
        let marks = SessionRecordMarks(bySetID: [UUID(): [1]], hasLoaded: false)

        #expect(marks.repCounts(forSetID: marks.bySetID.keys.first ?? UUID()).isEmpty)
    }

    /// Dropping the workout drops the marks with it: a badge is a claim about the workout on screen.
    @Test("Discarding the workout clears the marks")
    func discardingClearsTheMarks() async throws {
        let (workout, entryID) = try await startedSquat()
        await workout.store.addSet(
            toEntryID: entryID,
            values: SetEntryValues(
                weight: Weight(grams: 100_000), reps: 5, rpe: nil, isWarmup: false))
        #expect(!workout.store.personalRecords.bySetID.isEmpty)

        await workout.store.discard()

        #expect(workout.store.personalRecords.bySetID.isEmpty)
        #expect(!workout.store.personalRecords.hasLoaded)
    }
}

extension Array {
    /// The element at `index`, or `nil` where there is none — so a fixture's assumption about how
    /// many sets it wrote fails as a `#require` rather than as a trap.
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
