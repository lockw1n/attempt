import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// `FR-1.7.1` on screen: which of the section's four states is current, and which sentence the
/// insufficient one carries (`FR-1.13.3`).
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

    @Test("A computed estimate is drawn with the formula and window that produced it")
    func anEstimateCarriesItsProvenance() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.trainWeighted(squat, onDay: 0, work: [(reps: 5, kilos: 100)])
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
                    days: 90))
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
                cache: fixture.stack.personalRecords))
        await failing.loadEstimate()

        #expect(ExerciseEstimateScreenState.current(failing) == .failed)
        #expect(ExerciseEstimateScreenState.current(state) != .failed)
    }
}
