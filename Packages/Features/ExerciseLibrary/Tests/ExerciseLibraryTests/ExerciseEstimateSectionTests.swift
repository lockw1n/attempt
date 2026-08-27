import DerivedValues
import Foundation
import Localization
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

    /// The other half of ``isSettled``: a store that has just refused to answer is not a number to
    /// offer an override over either.
    @Test("Nothing is offered to override over a failed read")
    func theOverrideIsWithheldFromTheErrorState() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let state = ExerciseRecordsState(
            exerciseID: squat.id,
            recomputer: PersonalRecordRecomputer(
                workouts: RefusingWorkouts(failure: .recordNotFound(id: squat.id)),
                exercises: fixture.stack.exercises,
                cache: fixture.stack.personalRecords))

        await state.loadEstimate()

        #expect(ExerciseEstimateScreenState.current(state) == .failed)
        #expect(!ExerciseEstimateScreenState.current(state).isSettled)
    }

    /// **A refused write is reported without costing the reader the number.** The estimate on
    /// screen is unchanged — nothing was stored — which is why the diagnostic is its own property
    /// rather than the read's.
    @Test("A refused override is reported and leaves the number where it was")
    func aRefusedOverrideKeepsTheNumber() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.trainWeighted(squat, onDay: 0, work: [(reps: 5, kilos: 100)])
        let instant = fixture.day(0)
        let state = ExerciseRecordsState(
            exerciseID: squat.id,
            recomputer: PersonalRecordRecomputer(
                workouts: fixture.workouts,
                // Reads answer, writes refuse: the estimate loads and only the override fails.
                exercises: ScriptedExerciseRepository(
                    exercises: [squat], writeError: .recordNotFound(id: squat.id)),
                cache: fixture.stack.personalRecords,
                now: { instant }))
        await state.loadEstimate()
        let before = ExerciseEstimateScreenState.current(state)

        await state.setManualEstimate(Weight(grams: 140_000))

        #expect(state.manualFailure != nil)
        #expect(ExerciseEstimateScreenState.current(state) == before)
        #expect(!ExerciseEstimateScreenState.current(state).isManual)
    }

    /// A write that lands after one that failed clears the diagnostic — the retry is the same
    /// command, so nothing else would.
    @Test("An override that lands clears the previous failure")
    func aLandedOverrideClearsTheFailure() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let refusing = ScriptedExerciseRepository(
            exercises: [squat], writeError: .recordNotFound(id: squat.id))
        let instant = fixture.day(0)
        let state = ExerciseRecordsState(
            exerciseID: squat.id,
            recomputer: PersonalRecordRecomputer(
                workouts: fixture.workouts,
                exercises: refusing,
                cache: fixture.stack.personalRecords,
                now: { instant }))
        await state.setManualEstimate(Weight(grams: 140_000))
        #expect(state.manualFailure != nil)

        await refusing.recoverWrites()
        await state.setManualEstimate(Weight(grams: 140_000))

        #expect(state.manualFailure == nil)
        #expect(ExerciseEstimateScreenState.current(state) == .manual(Weight(grams: 140_000)))
    }

    // MARK: - The override field's opening contents

    /// **The field opens agreeing with the tile above it.** A computed estimate lands on `G-3.3`'s
    /// display step only by accident, so a field seeded with the exact grams would read `116.667`
    /// under a tile reading `116.5` — and Save with no edit would store a number the user never
    /// saw.
    @Test("The override field opens at the step the number is displayed at")
    func thePrefillMatchesTheDisplayedNumber() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.trainWeighted(squat, onDay: 0, work: [(reps: 5, kilos: 100)])
        let state = fixture.records(of: squat, through: fixture.recomputer())
        await state.loadEstimate()
        let screen = ExerciseEstimateScreenState.current(state)
        // Epley over 100 kg × 5 is 116.667 kg exactly, which is not on the half-kilo step.
        #expect(screen.weight == Weight(grams: 116_667))

        let prefill = screen.prefill(in: .kilograms, locale: Locale(identifier: "en_GB"))

        #expect(prefill == "116.5")
        #expect(prefill == Weight(grams: 116_667).formatted(in: .kilograms, precision: .half))
    }

    /// The same in a comma-decimal locale, since the field is read back in the user's own (`G-3.4`)
    /// and a prefill written with a period would be refused by the parser that reads it.
    @Test("The override field opens in the reader's own locale")
    func thePrefillIsLocalised() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.trainWeighted(squat, onDay: 0, work: [(reps: 5, kilos: 100)])
        let state = fixture.records(of: squat, through: fixture.recomputer())
        await state.loadEstimate()
        let german = Locale(identifier: "de_DE")

        let prefill = ExerciseEstimateScreenState.current(state)
            .prefill(in: .kilograms, locale: german)

        #expect(prefill == "116,5")
        #expect(
            LocalizedNumberField.weight(prefill, in: .kilograms, locale: german)
                == Weight(grams: 116_500))
    }

    /// An override is edited over, not cleared and retyped — see the section's `override` controls.
    @Test("The field opens over an override too, holding the override")
    func thePrefillReadsAnOverride() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let state = fixture.records(of: squat, through: fixture.recomputer())
        await state.setManualEstimate(Weight(grams: 142_500))

        let screen = ExerciseEstimateScreenState.current(state)

        #expect(screen.isManual)
        #expect(screen.weight == Weight(grams: 142_500))
        #expect(screen.prefill(in: .kilograms, locale: Locale(identifier: "en_GB")) == "142.5")
    }

    /// Nothing on screen is nothing to type over — the field opens blank rather than at zero, which
    /// is a real load a user could otherwise save by accident.
    @Test("The field opens empty where there is no number")
    func thePrefillIsEmptyWithoutANumber() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let state = fixture.records(of: squat, through: fixture.recomputer())
        await state.loadEstimate()

        let screen = ExerciseEstimateScreenState.current(state)

        #expect(screen == .insufficient(.noSetsLogged, days: 90))
        #expect(screen.prefill(in: .kilograms, locale: Locale(identifier: "en_GB")).isEmpty)
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
