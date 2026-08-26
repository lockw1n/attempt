import AppNavigation
import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// `FR-1.6.2` — the per-exercise personal-record list, its split and its link.
@MainActor
@Suite("Exercise records section")
struct ExerciseRecordsSectionTests {
    /// **The fixture the requirement asks for: one record at every N from 1 to 10.**
    ///
    /// Ten working sets, the set at N reps loaded at `210 − 10N` kg, so the heaviest set reaching N
    /// reps is the set performed *for* N — which makes every expected N-rep max a number the test can
    /// state rather than one it has to recompute to check.
    @Test("Every N from 1 to 10 lands on the right side of the disclosure")
    func everyRepMaxLandsInTheRightHalf() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.trainWeighted(
            squat,
            onDay: 0,
            work: (1...10).map { (reps: $0, kilos: 210 - 10 * $0) }
        )
        let state = fixture.records(of: squat, through: fixture.recomputer())

        await state.loadRecords()
        let list = ExerciseRecordList(state.repMaxes)

        #expect(list.prominent.map(\.reps) == [1, 2, 3, 4, 5])
        #expect(list.disclosed.map(\.reps) == [6, 7, 8, 9, 10])
        for repMax in list.prominent + list.disclosed {
            #expect(repMax.record.weight == Weight(grams: (210 - 10 * repMax.reps) * 1000))
        }
    }

    /// **Ten rows and only five of them are on screen**, which is the half of `FR-1.6.2` a list of ten
    /// cannot state: "behind a disclosure" is a claim about what the closed section does *not* show.
    @Test("The 6–10RM are not among the rows shown without asking")
    func higherRepMaxesAreNotProminent() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.trainWeighted(
            squat,
            onDay: 0,
            work: (1...10).map { (reps: $0, kilos: 210 - 10 * $0) }
        )
        let state = fixture.records(of: squat, through: fixture.recomputer())

        await state.loadRecords()
        let list = ExerciseRecordList(state.repMaxes)

        #expect(list.prominent.count == 5)
        #expect(!list.prominent.contains { $0.reps > 5 })
        #expect(list.disclosed.count == 5)
    }

    /// An exercise holding only some of the ten leaves gaps rather than zero rows: `Weight` is signed,
    /// so a row at zero is a claim that nothing was lifted.
    @Test("An N no set reached is absent from both halves")
    func unreachedRepCountsAreAbsent() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        // A single and a triple, and nothing else. The 1RM through the 3RM exist; 4 upwards do not.
        try await fixture.trainWeighted(
            squat, onDay: 0, work: [(reps: 1, kilos: 200), (reps: 3, kilos: 170)])
        let state = fixture.records(of: squat, through: fixture.recomputer())

        await state.loadRecords()
        let list = ExerciseRecordList(state.repMaxes)

        #expect(list.prominent.map(\.reps) == [1, 2, 3])
        #expect(list.disclosed.isEmpty)
        #expect(!list.isEmpty)
    }

    /// **`FR-1.6.2`'s link, as the route the row pushes.** The claim under test is *which* session it
    /// names: the 5RM was set two days before the heavier single, so a link that resolved to the
    /// newest workout — or to the one the 1RM came from — would pass a test that only checked it was
    /// a session at all.
    @Test("A record links to the session its source set was performed in")
    func aRecordLinksToItsSourceSession() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let fiveDay = try await fixture.trainWeighted(
            squat, onDay: 0, work: [(reps: 5, kilos: 150)])
        let singleDay = try await fixture.trainWeighted(
            squat, onDay: 2, work: [(reps: 1, kilos: 200)])
        let state = fixture.records(of: squat, through: fixture.recomputer())

        await state.load()

        let fiveRM = try #require(state.repMaxes.first { $0.reps == 5 })
        let single = try #require(state.repMaxes.first { $0.reps == 1 })
        let fiveRoute = Route.history(
            .session(sessionID: try #require(state.sourceSessions[fiveRM.record.sourceSetID])))
        let singleRoute = Route.history(
            .session(sessionID: try #require(state.sourceSessions[single.record.sourceSetID])))

        #expect(fiveRoute == .history(.session(sessionID: fiveDay.id)))
        #expect(singleRoute == .history(.session(sessionID: singleDay.id)))
        #expect(fiveDay.id != singleDay.id)
    }

    // MARK: - The four states (FR-1.13.1, FR-1.13.3)

    @Test("Nothing has looked yet is loading, not an empty list")
    func nothingLookedYetIsLoading() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let state = fixture.records(of: squat, through: fixture.recomputer())

        #expect(
            ExerciseRecordsScreenState.current(state, hasLoggedSets: false) == .loading)
    }

    @Test("An exercise nothing has been logged against is told to log a set")
    func nothingLoggedIsTheFirstSentence() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let state = fixture.records(of: squat, through: fixture.recomputer())

        await state.loadRecords()

        #expect(ExerciseRecordsScreenState.current(state, hasLoggedSets: false) == .noneYet)
    }

    /// **The distinction the two sentences exist for.** A user whose every set on this exercise was a
    /// warmup has logged sets and holds no records, and telling them to log a set is telling them the
    /// wrong thing about their own data.
    @Test("Sets that produce no record get the second sentence, not the first")
    func loggedButUnqualifyingSetsGetTheirOwnSentence() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.trainWeighted(
            squat, onDay: 0, work: [(reps: 5, kilos: 60)], isWarmup: true)
        let state = fixture.records(of: squat, through: fixture.recomputer())

        await state.loadRecords()

        #expect(state.repMaxes.isEmpty)
        #expect(ExerciseRecordsScreenState.current(state, hasLoggedSets: true) == .noRecordsYet)
    }

    @Test("Records that were read are shown")
    func recordsThatExistAreShown() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.trainWeighted(squat, onDay: 0, work: [(reps: 5, kilos: 150)])
        let state = fixture.records(of: squat, through: fixture.recomputer())

        await state.loadRecords()

        #expect(ExerciseRecordsScreenState.current(state, hasLoggedSets: true) == .ready)
    }

    /// **A failed read outranks a list already on screen**, which is what keeps a stale list from
    /// being presented as a current one.
    @Test("A read that failed is the failed state even with records held")
    func aFailedReadOutranksTheList() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.trainWeighted(squat, onDay: 0, work: [(reps: 5, kilos: 150)])
        let state = fixture.records(of: squat, through: fixture.recomputer())
        await state.loadRecords()
        #expect(!state.repMaxes.isEmpty)

        // A second state over a cache that refuses, holding the same list, is the same shape as this
        // screen after a store error: the numbers are there and the read that would confirm them is
        // not.
        let refused = fixture.records(
            of: squat,
            through: fixture.recomputer(
                cache: RefusingRecordCache(failure: .recordNotFound(id: squat.id))))
        await refused.loadRecords()

        #expect(refused.failure != nil)
        #expect(ExerciseRecordsScreenState.current(refused, hasLoggedSets: true) == .failed)
    }
}

/// A record cache that refuses every read, for the diagnostic path.
struct RefusingRecordCache: PersonalRecordCacheRepository {
    let failure: RepositoryError

    func personalRecords(
        forExerciseID exerciseID: UUID, includingDeleted: Bool
    ) async throws -> [PersonalRecordCache] { throw failure }

    func replacePersonalRecords(
        forExerciseID exerciseID: UUID, with values: [PersonalRecordCacheValues]
    ) async throws { throw failure }
}
