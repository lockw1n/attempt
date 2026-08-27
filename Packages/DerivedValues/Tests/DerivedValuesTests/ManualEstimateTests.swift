import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues

/// `FR-1.7.5`: the one e1RM the app does not compute, and the way back from it.
@Suite("Manual e1RM override")
struct ManualEstimateTests {
    @Test("An override is what the estimate reports, in place of the computed number")
    func anOverrideReplacesTheComputedNumber() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: daysAgo(1), sets: [working(100_000, 5)])
        let subject = recomputer(over: log)

        try await subject.setManualEstimate(Weight(grams: 140_000), forExerciseID: exerciseID)

        let estimate = try await subject.estimatedMax(forExerciseID: exerciseID)
        #expect(estimate.manual == Weight(grams: 140_000))
        #expect(estimate.weight == Weight(grams: 140_000))
        #expect(estimate.isManual)
        // The computed accessor answers `nil`, which is what keeps a caller from reading an
        // override as a record with a source set.
        #expect(estimate.record == nil)
    }

    /// The bypass is the point: a set the calculator refuses and a window it falls outside of are
    /// both reasons there is no *computed* estimate, and neither is a reason there is no number.
    @Test("An override answers where nothing could be computed at all")
    func anOverrideOutranksEveryRefusal() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        // Twelve reps: past the rep range. And a year old: outside the window either way.
        try await log.session(of: exerciseID, on: daysAgo(400), sets: [working(100_000, 12)])
        let subject = recomputer(over: log)
        #expect(try await subject.estimatedMax(forExerciseID: exerciseID).absence != nil)

        try await subject.setManualEstimate(Weight(grams: 90_000), forExerciseID: exerciseID)

        #expect(try await subject.estimatedMax(forExerciseID: exerciseID).manual == Weight(grams: 90_000))
    }

    @Test("Clearing the override returns the exercise to its computed estimate")
    func clearingReturnsTheComputedEstimate() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: daysAgo(1), sets: [working(100_000, 5)])
        let subject = recomputer(over: log)
        try await subject.setManualEstimate(Weight(grams: 140_000), forExerciseID: exerciseID)

        try await subject.setManualEstimate(nil, forExerciseID: exerciseID)

        let estimate = try await subject.estimatedMax(forExerciseID: exerciseID)
        #expect(estimate.manual == nil)
        #expect(estimate.record?.weight == Weight(grams: 116_667))
        // Nothing left behind on the row either: a cleared override is the column every exercise
        // that has never been overridden carries.
        let stored = try await log.repositories.exercises.exercise(
            id: exerciseID, includingDeleted: false)
        #expect(stored?.manualE1RM == nil)
    }

    /// An override is not a record: `FR-1.6.1` reads logged sets and a number the user typed is not
    /// one, so the 5RM below is still the set's.
    @Test("An override moves no rep max")
    func anOverrideIsNotARecord() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: daysAgo(1), sets: [working(100_000, 5)])
        let subject = recomputer(over: log)

        try await subject.setManualEstimate(Weight(grams: 200_000), forExerciseID: exerciseID)

        let repMaxes = try await subject.repMaxes(forExerciseID: exerciseID)
        #expect(repMaxes.first { $0.reps == 5 }?.record.weight == Weight(grams: 100_000))
    }

    @Test("Setting an override tells every screen showing that exercise to read again")
    func anOverrideIsAnnounced() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let subject = recomputer(over: log)
        var changes = await subject.changes().makeAsyncIterator()

        try await subject.setManualEstimate(Weight(grams: 140_000), forExerciseID: exerciseID)

        #expect(await changes.next() == .exercise(exerciseID))
    }

    /// **A no-op write is silent, and the reason is not tidiness.** Assigning a `@Model` property
    /// marks the row changed whatever the value was, so an unconditional save restamps `updatedAt`
    /// — `G-2.4`'s conflict key — and a local write that moved nothing would outrank a real remote
    /// edit.
    ///
    /// **The silent call is followed by a *distinguishable* one**, on
    /// ``PersonalRecordPublicationTests``' rule. Asserting that the next value is
    /// `.exercise(exerciseID)` would pass either way — that is what both calls publish — so the
    /// test could not fail and the guard could be deleted under it. A formula change publishes
    /// ``RecordChange/everyExercise``, which only arrives first if the override published nothing.
    @Test("An override already in force writes nothing and announces nothing")
    func anUnchangedOverrideIsSilent() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let subject = recomputer(over: log)
        try await subject.setManualEstimate(Weight(grams: 140_000), forExerciseID: exerciseID)
        let stamped = try await log.repositories.exercises.exercise(
            id: exerciseID, includingDeleted: false)
        var changes = await subject.changes().makeAsyncIterator()

        try await subject.setManualEstimate(Weight(grams: 140_000), forExerciseID: exerciseID)
        await subject.formulaDidChange(to: .lombardi)

        #expect(await changes.next() == .everyExercise)
        // And the row did not move either: `updatedAt` is `G-2.4`'s conflict key, so a local no-op
        // that restamped it would outrank a real remote edit.
        let after = try await log.repositories.exercises.exercise(
            id: exerciseID, includingDeleted: false)
        #expect(after?.updatedAt == stamped?.updatedAt)
        #expect(after?.manualE1RM == Weight(grams: 140_000))
    }

    /// The same holds for clearing an override that is not there — the state a fresh exercise is
    /// already in. Distinguishable follow-up for the reason above.
    @Test("Clearing an override nobody set announces nothing")
    func clearingWhatIsNotThereIsSilent() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let stamped = try await log.repositories.exercises.exercise(
            id: exerciseID, includingDeleted: false)
        let subject = recomputer(over: log)
        var changes = await subject.changes().makeAsyncIterator()

        try await subject.setManualEstimate(nil, forExerciseID: exerciseID)
        await subject.formulaDidChange(to: .lombardi)

        #expect(await changes.next() == .everyExercise)
        let after = try await log.repositories.exercises.exercise(
            id: exerciseID, includingDeleted: false)
        #expect(after?.updatedAt == stamped?.updatedAt)
    }

    /// The other side of the guard: a *changed* override does write and does announce, so the
    /// silence above is the no-op's alone rather than the command's.
    @Test("A changed override writes and announces")
    func aChangedOverrideIsAnnounced() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let subject = recomputer(over: log)
        try await subject.setManualEstimate(Weight(grams: 140_000), forExerciseID: exerciseID)
        var changes = await subject.changes().makeAsyncIterator()

        try await subject.setManualEstimate(Weight(grams: 150_000), forExerciseID: exerciseID)
        await subject.formulaDidChange(to: .lombardi)

        #expect(await changes.next() == .exercise(exerciseID))
        #expect(
            try await subject.estimatedMax(forExerciseID: exerciseID).manual
                == Weight(grams: 150_000))
    }

    @Test("An override against an exercise that does not exist is refused")
    func anOverrideNeedsAnExercise() async throws {
        let subject = recomputer(over: TrainingLog())
        let missing = UUID()

        await #expect(throws: RepositoryError.recordNotFound(id: missing)) {
            try await subject.setManualEstimate(Weight(grams: 100_000), forExerciseID: missing)
        }
    }

    /// **A catalogue that cannot be read costs the estimate**, rather than quietly answering with
    /// the computed number — which would be a value the user may already have replaced. See
    /// ``PersonalRecordRecomputer/manualEstimate(forExerciseID:)``.
    @Test("An unreadable catalogue fails the estimate rather than falling back")
    func anUnreadableCatalogueFailsTheEstimate() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: daysAgo(1), sets: [working(100_000, 5)])
        let subject = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: RefusingExercises(failure: .recordNotFound(id: exerciseID)),
            cache: log.repositories.personalRecords,
            now: { fixtureNow })

        await #expect(throws: (any Error).self) {
            try await subject.estimatedMax(forExerciseID: exerciseID)
        }
    }

    // MARK: - Fixtures

    /// A recomputer over `log`, with "now" pinned to the fixture reference.
    private func recomputer(over log: TrainingLog) -> PersonalRecordRecomputer {
        PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
    }
}
