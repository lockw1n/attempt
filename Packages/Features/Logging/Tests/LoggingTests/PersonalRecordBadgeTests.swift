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

    /// The schemes the store says `setID` holds the record at.
    private func marks(_ workout: Workout, _ setID: UUID) -> [RecordScheme] {
        workout.store.personalRecords.schemes(forSetID: setID)
    }

    /// The N's among them that stand at a single set — `FR-1.6.1`'s column of `FR-16.2.1`'s table,
    /// which is what a lone set can hold.
    private func repMaxMarks(_ workout: Workout, _ setID: UUID) -> [Int] {
        marks(workout, setID).filter { $0.sets == 1 }.map(\.reps)
    }

    /// What the badge over `setID` says, or `nil` where none is drawn.
    private func badge(_ workout: Workout, _ setID: UUID) -> RecordBadge? {
        RecordBadge(schemes: marks(workout, setID))
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
        #expect(repMaxMarks(workout, logged.id) == [1, 2, 3, 4, 5])
        // `FR-16.2.4`: the badge names the maximal cell, which for a lone set is the top N — not
        // the five it also holds, and not `5 × 1`, which is nobody's notation for a single set.
        #expect(badge(workout, logged.id)?.scheme == RecordScheme(reps: 5, sets: 1))
        #expect(String(localized: try #require(badge(workout, logged.id)).text) == "PR 5RM")
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
        #expect(repMaxMarks(workout, first.id) == [1, 2, 3])

        await workout.store.addSet(
            toEntryID: entryID,
            values: SetEntryValues(
                weight: Weight(grams: 110_000), reps: 3, rpe: nil, isWarmup: false))

        let heavier = try await loggedSet(workout, entryID, at: 1)
        #expect(repMaxMarks(workout, heavier.id) == [1, 2, 3])
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
        let marks = SessionRecordMarks(
            bySetID: [UUID(): [RecordScheme(reps: 1, sets: 1)]], hasLoaded: false)

        #expect(marks.schemes(forSetID: marks.bySetID.keys.first ?? UUID()).isEmpty)
    }

    /// **`FR-16.2.4`'s own case: a run's badge names the run, not the heaviest single in it.** Three
    /// consecutive equal sets hold cells up to `5 × 3`, and the badge on every one of them — the
    /// cache names a run by its first set — is the corner rather than the `5 × 1` the same load also
    /// took.
    @Test("A run of three equal sets is badged with its maximal scheme")
    func aRunIsBadgedWithItsMaximalScheme() async throws {
        let (workout, entryID) = try await startedSquat()
        for _ in 0..<3 {
            await workout.store.addSet(
                toEntryID: entryID,
                values: SetEntryValues(
                    weight: Weight(grams: 100_000), reps: 5, rpe: nil, isWarmup: false))
        }

        let first = try await loggedSet(workout, entryID, at: 0)
        let mark = try #require(badge(workout, first.id))
        #expect(mark.scheme == RecordScheme(reps: 5, sets: 3))
        #expect(String(localized: mark.text) == "PR 5×3")
        #expect(String(localized: mark.label) == "Personal record, 5 by 3")
    }

    /// **A run whose every cell stands at two sets and up still carries a badge**, which is the gap
    /// `T-16.05` left open: read through `FR-1.6.1`'s one-set column this run holds nothing, because
    /// a heavier single of five already stands there.
    @Test("A run beaten at one set is still badged at the schemes it took")
    func aRunBeatenAtOneSetKeepsItsSchemeBadge() async throws {
        let (workout, entryID) = try await startedSquat()
        await workout.store.addSet(
            toEntryID: entryID,
            values: SetEntryValues(
                weight: Weight(grams: 120_000), reps: 5, rpe: nil, isWarmup: false))
        for _ in 0..<2 {
            await workout.store.addSet(
                toEntryID: entryID,
                values: SetEntryValues(
                    weight: Weight(grams: 100_000), reps: 5, rpe: nil, isWarmup: false))
        }

        let runStart = try await loggedSet(workout, entryID, at: 1)
        #expect(repMaxMarks(workout, runStart.id).isEmpty)
        #expect(badge(workout, runStart.id)?.scheme == RecordScheme(reps: 5, sets: 2))
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
