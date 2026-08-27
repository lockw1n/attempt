import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// `FR-1.7.1` on screen: which of the section's five states is current, which sentence the
/// insufficient one carries (`FR-1.13.3`), and what `FR-1.7.4`'s link and `FR-1.7.5`'s override do
/// to both.
@MainActor
@Suite("Exercise estimate section")
struct ExerciseEstimateSectionTests {
    @Test("Before the first read the section is loading, not empty")
    func nothingReadYetIsLoading() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let state = fixture.records(of: squat, through: fixture.recomputer())

        #expect(ExerciseEstimateScreenState.current(state) == .loading)
    }

    /// The `sessionID` is `FR-1.7.4`'s half: it is the session the fixture actually wrote, not
    /// whatever the state happens to hold — an assertion against the state's own answer would be
    /// satisfied by a link that resolved to nothing.
    @Test("A computed estimate is drawn with the formula, window and source set that produced it")
    func anEstimateCarriesItsProvenance() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let session = try await fixture.trainWeighted(
            squat, onDay: 0, work: [(reps: 5, kilos: 100)])
        let state = fixture.records(of: squat, through: fixture.recomputer(formula: .brzycki))

        await state.loadEstimate()

        #expect(
            ExerciseEstimateScreenState.current(state)
                == .ready(
                    DatedRecord(
                        weight: Weight(grams: 112_500),
                        sourceSetID: try #require(state.estimatedMax?.sourceSetID),
                        achievedAt: fixture.day(0)),
                    formula: .brzycki,
                    days: 90,
                    sessionID: session.id))
    }

    /// `FR-1.7.5` on screen: the override replaces the number *and* the provenance line, since
    /// neither the formula nor the window took part in it.
    @Test("An override is drawn as manual, in place of the computed estimate")
    func anOverrideReplacesTheEstimate() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.trainWeighted(squat, onDay: 0, work: [(reps: 5, kilos: 100)])
        let state = fixture.records(of: squat, through: fixture.recomputer())
        await state.loadEstimate()

        await state.setManualEstimate(Weight(grams: 140_000))

        #expect(ExerciseEstimateScreenState.current(state) == .manual(Weight(grams: 140_000)))
        #expect(ExerciseEstimateScreenState.current(state).isManual)
        #expect(state.manualFailure == nil)
    }

    /// The way back, and that it leaves nothing behind: the section returns to the *computed*
    /// state, links included, rather than to a manual state holding the computed number.
    @Test("Reverting restores the computed estimate with no manual artifact")
    func revertingRestoresTheComputedEstimate() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let session = try await fixture.trainWeighted(
            squat, onDay: 0, work: [(reps: 5, kilos: 100)])
        let state = fixture.records(of: squat, through: fixture.recomputer())
        await state.setManualEstimate(Weight(grams: 140_000))

        await state.setManualEstimate(nil)

        #expect(
            ExerciseEstimateScreenState.current(state)
                == .ready(
                    DatedRecord(
                        weight: Weight(grams: 116_667),
                        sourceSetID: try #require(state.estimatedMax?.sourceSetID),
                        achievedAt: fixture.day(0)),
                    formula: .defaultFormula,
                    days: 90,
                    sessionID: session.id))
        #expect(!ExerciseEstimateScreenState.current(state).isManual)
    }

    /// An override answers for an exercise that has nothing to compute from at all — which is the
    /// whole of what "takes precedence" means when there is no computed number to take it over.
    @Test("An override outranks an absence, not only a number")
    func anOverrideOutranksAnAbsence() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let state = fixture.records(of: squat, through: fixture.recomputer())
        await state.loadEstimate()
        #expect(ExerciseEstimateScreenState.current(state) == .insufficient(.noSetsLogged, days: 90))

        await state.setManualEstimate(Weight(grams: 100_000))

        #expect(ExerciseEstimateScreenState.current(state) == .manual(Weight(grams: 100_000)))
    }

    /// The override controls are drawn only once the section knows what is in force — see
    /// ``ExerciseEstimateScreenState/isSettled``.
    @Test("Nothing is offered to override until the estimate has settled")
    func theOverrideWaitsForTheRead() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let state = fixture.records(of: squat, through: fixture.recomputer())
        #expect(!ExerciseEstimateScreenState.current(state).isSettled)

        await state.loadEstimate()

        #expect(ExerciseEstimateScreenState.current(state).isSettled)
    }

    /// **The seven sentences are seven, and the test that would have caught the old copy.** Before
    /// this task every one of these drew "Log a completed working set and an estimate appears here",
    /// which is only true of the first.
    @Test("Every reason an estimate is missing gets its own sentence")
    func everyAbsenceHasItsOwnSentence() {
        let sentences =
            ([.noSetsLogged, .noneInWindow] as [EstimateAbsence]
            + E1RMRefusal.allCases.map(EstimateAbsence.refused))
            .map { String(localized: ExerciseLibraryStrings.e1rmAbsence($0, days: 90)) }

        #expect(Set(sentences).count == sentences.count)
        #expect(sentences.allSatisfy { !$0.isEmpty })
    }

    /// `TR-1.12`'s wrap reference is recorded over one of the seven, and it is only a worst case
    /// while it is over the longest — which was not true when it was first recorded. Asserted here
    /// rather than left to the eye, since re-wording any sentence can move the answer.
    @Test("The rep-range sentence is the longest, which is the one the snapshot renders")
    func theSnapshottedSentenceIsTheLongest() {
        let longest = ExerciseLibraryStrings.absences
            .map { String(localized: ExerciseLibraryStrings.e1rmAbsence($0, days: 90)) }
            .max(by: { $0.count < $1.count })

        #expect(
            longest
                == String(
                    localized: ExerciseLibraryStrings.e1rmAbsence(
                        .refused(.repsOutOfRange), days: 90)))
    }

    @Test("The window's length is named in the sentence rather than assumed")
    func theSentenceNamesTheWindow() {
        let ninety = String(localized: ExerciseLibraryStrings.e1rmAbsence(.noneInWindow, days: 90))
        let thirty = String(localized: ExerciseLibraryStrings.e1rmAbsence(.noneInWindow, days: 30))

        #expect(ninety.contains("90"))
        #expect(thirty.contains("30"))
    }

    /// A lifter who logged a twelve-rep set is told about the rep range, not that they have logged
    /// nothing — which is the refusal this screen used to hide.
    @Test("A refused set reads as a refusal, not as an empty exercise")
    func aRefusedSetIsNotAnEmptyExercise() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.trainWeighted(squat, onDay: 0, work: [(reps: 12, kilos: 100)])
        let state = fixture.records(of: squat, through: fixture.recomputer())

        await state.loadEstimate()

        #expect(
            ExerciseEstimateScreenState.current(state)
                == .insufficient(.refused(.repsOutOfRange), days: 90))
    }

    @Test("An exercise with no sets at all says exactly that")
    func nothingLoggedSaysSo() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let state = fixture.records(of: squat, through: fixture.recomputer())

        await state.loadEstimate()

        #expect(
            ExerciseEstimateScreenState.current(state) == .insufficient(.noSetsLogged, days: 90))
    }

    /// **The estimate's own failure, not the merged one**, and it outranks a number already on
    /// screen: a stale estimate under no diagnostic is the failure this section's whole point rules
    /// out.
    @Test("A read that fails reports a failure rather than the last good number")
    func aFailedReadOutranksTheLastAnswer() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.trainWeighted(squat, onDay: 0, work: [(reps: 5, kilos: 100)])
        let state = fixture.records(of: squat, through: fixture.recomputer())
        await state.loadEstimate()
        #expect(state.estimatedMax != nil)

        let failing = ExerciseRecordsState(
            exerciseID: squat.id,
            recomputer: PersonalRecordRecomputer(
                workouts: RefusingWorkouts(failure: .recordNotFound(id: squat.id)),
                exercises: fixture.stack.exercises,
                cache: fixture.stack.personalRecords))
        await failing.loadEstimate()

        #expect(ExerciseEstimateScreenState.current(failing) == .failed)
        #expect(ExerciseEstimateScreenState.current(state) != .failed)
    }
}
