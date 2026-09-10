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
/// path rather than about a view.** The logging commands hand the recompute to
/// `ActiveSessionStore.announceSetChange(inEntryID:)` and return without waiting for it, so the
/// interaction is the command's `await` *plus* that chain — which is what
/// `settleRecordRefresh()` below waits for. A mark that is not there once it has settled is a mark
/// the user would have had to refresh to see.
///
/// **Every read here settles first, and none of them may stop doing so.** The walk behind a set is
/// `NFR-1.6`'s budget and the tap is `NFR-1.2`'s, five times smaller; an assertion taken on the
/// command's own `await` would pass or fail on which continuation the main actor happened to run
/// first, which is a race that passes far more often than it fails.
///
/// Nothing here is optimistic even so: the value read is the recomputed one, from `G-1.5`'s cache,
/// and there is no provisional mark to correct afterwards. What moved is when it is published.
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

    /// The cells the store says `setID` stands at, once the recompute behind the write has landed.
    private func marks(_ workout: Workout, _ setID: UUID) async -> [SchemeMark] {
        await workout.store.settleRecordRefresh()
        return workout.store.personalRecords.marks(forSetID: setID)
    }

    /// The N's among them that stand at a single set — `FR-1.6.1`'s column of `FR-16.2.1`'s table,
    /// which since `FR-17.2.1` is at most one N.
    private func repMaxMarks(_ workout: Workout, _ setID: UUID) async -> [Int] {
        await marks(workout, setID).filter { $0.scheme.sets == 1 }.map(\.scheme.reps)
    }

    /// What the badge over `setID` says, or `nil` where none is drawn.
    private func badge(_ workout: Workout, _ setID: UUID) async -> RecordBadge? {
        RecordBadge(marks: await marks(workout, setID))
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
        // One N, since `FR-17.2.1`: a set of five is the five-rep record and nothing below it.
        #expect(await repMaxMarks(workout, logged.id) == [5])
        #expect(await badge(workout, logged.id)?.scheme == RecordScheme(reps: 5, sets: 1))
        // The first time this scheme is performed it is `FR-16.2.3`'s baseline, so the badge says
        // *First* rather than *PR* — which is what keeps it agreeing with the feed (`FR-16.3.4`).
        #expect(await badge(workout, logged.id)?.isFirstPerformance == true)
        #expect(String(localized: try #require(await badge(workout, logged.id)).text) == "First · 5 reps")
        #expect(
            String(localized: try #require(await badge(workout, logged.id)).label)
                == "First time, 5 reps")
    }

    /// `FR-17.2.2`'s two badge states over the one set that carries both in turn: performed once is
    /// a first performance, and the run that beats it is a record.
    @Test("A scheme beaten is a record; the same scheme performed first is not")
    func theBadgeTellsARecordFromAFirstPerformance() async throws {
        let (workout, entryID) = try await startedSquat()
        await workout.store.addSet(
            toEntryID: entryID,
            values: SetEntryValues(
                weight: Weight(grams: 80_000), reps: 5, rpe: nil, isWarmup: false))
        let first = try await loggedSet(workout, entryID, at: 0)
        #expect(await badge(workout, first.id)?.isFirstPerformance == true)

        await workout.store.addSet(
            toEntryID: entryID,
            values: SetEntryValues(
                weight: Weight(grams: 90_000), reps: 5, rpe: nil, isWarmup: false))

        let heavier = try await loggedSet(workout, entryID, at: 1)
        let mark = try #require(await badge(workout, heavier.id))
        #expect(mark.isFirstPerformance == false)
        #expect(String(localized: mark.text) == "PR · 5 reps")
        #expect(String(localized: mark.label) == "Personal record, 5 reps")
        // And the beaten set keeps no badge at all — the cache holds one row per cell.
        #expect(await marks(workout, first.id).isEmpty)
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
        #expect(await repMaxMarks(workout, first.id) == [3])

        await workout.store.addSet(
            toEntryID: entryID,
            values: SetEntryValues(
                weight: Weight(grams: 110_000), reps: 3, rpe: nil, isWarmup: false))

        let heavier = try await loggedSet(workout, entryID, at: 1)
        #expect(await repMaxMarks(workout, heavier.id) == [3])
        #expect(await marks(workout, first.id).isEmpty)
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
        #expect(await marks(workout, logged.id).isEmpty)
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
        #expect(!(await marks(workout, logged.id)).isEmpty)

        await workout.store.markSet(id: logged.id, inEntryID: entryID, isWarmup: true)

        #expect(await marks(workout, logged.id).isEmpty)
    }

    /// **Nothing has looked and nothing holds a record are the same empty dictionary**, so the flag
    /// is what separates them — the distinction `PreviousPerformances` makes on the same screen.
    @Test("A store that has not read yet reports no marks rather than an answer")
    func anUnreadStoreClaimsNothing() async throws {
        let marks = SessionRecordMarks(
            bySetID: [
                UUID(): [SchemeMark(scheme: RecordScheme(reps: 1, sets: 1), isFirstPerformance: true)]
            ],
            hasLoaded: false)

        #expect(marks.marks(forSetID: marks.bySetID.keys.first ?? UUID()).isEmpty)
    }

    /// **`FR-16.2.4`'s own case: a run's badge names the run.** Three consecutive equal sets hold
    /// the `5 × 3` cell — and, since `FR-17.2.1`, that cell alone — so the badge on the run's first
    /// set is `5×3` and no single-set spelling is available to it.
    @Test("A run of three equal sets is badged with its scheme")
    func aRunIsBadgedWithItsScheme() async throws {
        let (workout, entryID) = try await startedSquat()
        for _ in 0..<3 {
            await workout.store.addSet(
                toEntryID: entryID,
                values: SetEntryValues(
                    weight: Weight(grams: 100_000), reps: 5, rpe: nil, isWarmup: false))
        }

        let first = try await loggedSet(workout, entryID, at: 0)
        let mark = try #require(await badge(workout, first.id))
        #expect(mark.scheme == RecordScheme(reps: 5, sets: 3))
        #expect(await marks(workout, first.id).count == 1)
        #expect(String(localized: mark.text) == "First · 5×3")
        #expect(String(localized: mark.label) == "First time, 5 by 3")
    }

    /// **A run of two carries a badge though it holds no rep max at all**, which is the gap
    /// `T-16.05` left open and which `FR-17.2.1` widens: a run of two stands only at `5 × 2`, so
    /// read through `FR-1.6.1`'s one-set column it would carry nothing whatever else was logged.
    @Test("A run of two is badged at the scheme it took, holding no rep max")
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
        #expect(await repMaxMarks(workout, runStart.id).isEmpty)
        #expect(await badge(workout, runStart.id)?.scheme == RecordScheme(reps: 5, sets: 2))
    }

    /// **T-17.03's simulator walk, as an assertion.** The walk saw `First · 10×3` on a group written
    /// `12,0 kg × 12 × 3` — the badge naming the cell a twelve-rep run had been clamped to, two
    /// centimetres from the numeral `12`. That was the withdrawn dominance rule's clamp, and the
    /// same task's review replaced it with `FR-17.2.1`'s refusal before the finding was ever acted
    /// on, which is why the fix has no commit of its own to point at.
    ///
    /// Pinned **here** rather than only at ``PowerliftingCore/SchemeRecordCalculator/cell(for:)``,
    /// where `boundsRefuse` already holds it: the defect was a badge, and what a badge says is the
    /// end of a pipeline — the calculator, the cache, the marks read, `RecordBadge(marks:)`. A
    /// refusal at the head of it is not evidence about the tail.
    ///
    /// **Both bounds, since they are one rule read in two dimensions.** The walk only ever saw the
    /// rep half, and a test shaped around what was seen would leave the set half asserted nowhere
    /// but at the calculator — which is precisely the substitution the paragraph above refuses.
    @Test("A run past either bound draws no badge, rather than a badge naming a clamped cell")
    func aRunPastEitherBoundDrawsNoBadge() async throws {
        // The rep bound, which is the one the walk saw: twelve reps against a table ending at ten.
        let (long, longFirst) = try await runOfSquats(reps: 12, count: 3)
        // No cell at all — not the 10-rep row, and not the one-set column either.
        #expect(await marks(long, longFirst.id).isEmpty)
        #expect(await repMaxMarks(long, longFirst.id).isEmpty)
        #expect(await badge(long, longFirst.id) == nil)

        // The set bound, in the other dimension and on the same argument — eight sets is not six.
        // Asserted here because ``cell(for:)``'s refusal covers both bounds and this test's own
        // premise is that the head of the pipeline is not evidence about its tail: until T-1.92's
        // review only the rep half had a badge-end assertion, so half the claim rested on the
        // argument it was written to distrust.
        let (many, manyFirst) = try await runOfSquats(reps: 5, count: 7)
        #expect(await marks(many, manyFirst.id).isEmpty)
        #expect(await repMaxMarks(many, manyFirst.id).isEmpty)
        #expect(await badge(many, manyFirst.id) == nil)

        // And each run just inside its own bound still badges, so what is asserted above is the
        // bound rather than the fixture failing to write anything.
        let (atRepBound, atRepBoundFirst) = try await runOfSquats(reps: 10, count: 3)
        #expect(await badge(atRepBound, atRepBoundFirst.id)?.scheme == RecordScheme(reps: 10, sets: 3))
        let (atSetBound, atSetBoundFirst) = try await runOfSquats(reps: 5, count: 6)
        #expect(await badge(atSetBound, atSetBoundFirst.id)?.scheme == RecordScheme(reps: 5, sets: 6))
    }

    /// A workout holding one run of `count` identical sets at `reps`, and the set the run starts at.
    ///
    /// One load for every fixture here, because the bound under test is the run's shape and a second
    /// varying quantity would be a second reason a mark could be absent.
    private func runOfSquats(reps: Int, count: Int) async throws -> (Workout, SetEntry) {
        let (workout, entryID) = try await startedSquat()
        for _ in 0..<count {
            await workout.store.addSet(
                toEntryID: entryID,
                values: SetEntryValues(
                    weight: Weight(grams: 120_000), reps: reps, rpe: nil, isWarmup: false))
        }
        return (workout, try await loggedSet(workout, entryID, at: 0))
    }

    /// Dropping the workout drops the marks with it: a badge is a claim about the workout on screen.
    @Test("Discarding the workout clears the marks")
    func discardingClearsTheMarks() async throws {
        let (workout, entryID) = try await startedSquat()
        await workout.store.addSet(
            toEntryID: entryID,
            values: SetEntryValues(
                weight: Weight(grams: 100_000), reps: 5, rpe: nil, isWarmup: false))
        await workout.store.settleRecordRefresh()
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
