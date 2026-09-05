import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// `FR-15.1.4`, `FR-15.1.5` and `FR-16.7.2` on screen: which of the section's four states is
/// current, what the change sheet writes, and what a backdated change replaces.
@MainActor
@Suite("Training max section")
struct TrainingMaxSectionTests {
    @Test("Before the first read the section is loading, not absent")
    func nothingReadYetIsLoading() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")

        #expect(TrainingMaxScreenState.current(fixture.trainingMax(of: squat)) == .loading)
    }

    @Test("An exercise that has never had one says so rather than showing a zero")
    func noTrainingMaxIsItsOwnState() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let state = fixture.trainingMax(of: squat)

        await state.load()

        #expect(TrainingMaxScreenState.current(state) == TrainingMaxScreenState.none)
        #expect(state.current == nil)
    }

    @Test("The number in force is drawn with the day it took effect and the note behind it")
    func theNumberCarriesItsIndicator() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let entry = try await fixture.writeTrainingMax(
            squat, kilos: 180, onDay: 0, reason: "coach")
        let state = fixture.trainingMax(of: squat, today: 3)

        await state.load()

        // By identity and by field rather than by whole value: the repository stamps `updatedAt`
        // on the way in, so the row read back is deliberately not the one handed to it.
        #expect(state.current?.id == entry.id)
        #expect(state.history.map(\.id) == [entry.id])
        #expect(state.current?.newWeight == Weight(grams: 180_000))
        #expect(state.current?.reason == "coach")
        #expect(state.current?.effectiveFrom == fixture.day(0))
    }

    /// The history is newest-first, so its first row can be one that takes effect *next* week —
    /// which is not what is in force today. Two reads rather than one, and this is the test that
    /// separates them.
    @Test("A change dated in the future is in the history and not yet in force")
    func afutureChangeIsNotInForce() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.writeTrainingMax(squat, kilos: 180, onDay: 0)
        let next = try await fixture.writeTrainingMax(
            squat, kilos: 185, onDay: 7, replacing: 180)
        let state = fixture.trainingMax(of: squat, today: 3)

        await state.load()

        #expect(state.current?.newWeight == Weight(grams: 180_000))
        #expect(state.history.first?.id == next.id)
        #expect(state.history.count == 2)
    }

    @Test("A read that fails reports a failure rather than an absence")
    func afailedReadIsNotAnAbsence() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let state = TrainingMaxSectionState(
            exerciseID: squat.id,
            trainingMaxes: FailingTrainingMaxRepository(),
            settings: fixture.settings,
            records: fixture.recomputer())

        await state.load()

        #expect(TrainingMaxScreenState.current(state) == .failed)
        #expect(state.readFailure != nil)
    }

    // MARK: - The change (FR-16.7.2)

    @Test("The first change for an exercise replaces nothing, and says so with nil rather than zero")
    func thefirstChangeHasNoOldWeight() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let state = fixture.trainingMax(of: squat)
        var draft = fixture.draft(onDay: 0)
        draft.weightText = "180"
        draft.reason = "coach"

        let saved = await state.save(draft)

        #expect(saved)
        #expect(state.current?.newWeight == Weight(grams: 180_000))
        #expect(state.current?.oldWeight == nil)
        #expect(state.current?.reason == "coach")
    }

    @Test("A second change records what it replaced")
    func asecondChangeCarriesTheOldWeight() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.writeTrainingMax(squat, kilos: 170, onDay: 0)
        let state = fixture.trainingMax(of: squat, today: 8)
        var draft = fixture.draft(onDay: 7)
        draft.weightText = "180"

        _ = await state.save(draft)

        #expect(state.current?.oldWeight == Weight(grams: 170_000))
        #expect(state.current?.newWeight == Weight(grams: 180_000))
        #expect(state.current?.reason.isEmpty == true)
    }

    /// A change backdated into a block replaces whatever was in force *then*, which is not
    /// necessarily the number on screen.
    @Test("A backdated change replaces what was in force on its own day")
    func abackdatedChangeReplacesItsOwnPredecessor() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.writeTrainingMax(squat, kilos: 160, onDay: 0)
        try await fixture.writeTrainingMax(squat, kilos: 180, onDay: 14, replacing: 160)
        let state = fixture.trainingMax(of: squat, today: 20)
        var draft = fixture.draft(onDay: 7)
        draft.weightText = "170"

        _ = await state.save(draft)

        let backdated = try #require(
            state.history.first { $0.effectiveFrom == TrainingHistory.gmt.startOfDay(for: fixture.day(7)) })
        #expect(backdated.oldWeight == Weight(grams: 160_000))
        // And the number on screen is still the later one, which the backdated row did not replace.
        #expect(state.current?.newWeight == Weight(grams: 180_000))
    }

    @Test("The day the change takes effect is the start of that day, not the moment it was typed")
    func theeffectiveDateIsADay() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let state = fixture.trainingMax(of: squat, today: 2)
        var draft = fixture.draft(onDay: 0, atSecondsIntoTheDay: 53_000)
        draft.weightText = "180"

        _ = await state.save(draft)

        #expect(
            state.current?.effectiveFrom
                == TrainingHistory.gmt.startOfDay(for: fixture.day(0).addingTimeInterval(53_000)))
    }

    @Test("A refused write leaves the number where it was and reports itself")
    func arefusedWriteKeepsTheNumber() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let state = TrainingMaxSectionState(
            exerciseID: squat.id,
            trainingMaxes: FailingTrainingMaxRepository(reads: fixture.stack.trainingMaxes),
            settings: fixture.settings,
            records: fixture.recomputer())
        var draft = fixture.draft(onDay: 0)
        draft.weightText = "180"

        await state.load()
        let saved = await state.save(draft)

        #expect(!saved)
        #expect(state.writeFailure != nil)
        #expect(TrainingMaxScreenState.current(state) == TrainingMaxScreenState.none)
    }

    @Test("A number in pounds is read in pounds")
    func thefieldIsReadInTheDisplayUnit() async throws {
        let fixture = TrainingHistory()
        let squat = try await fixture.exercise(named: "Back Squat")
        let state = fixture.trainingMax(of: squat)
        var draft = fixture.draft(onDay: 0, unit: .pounds)
        draft.weightText = "405"

        _ = await state.save(draft)

        #expect(state.current?.newWeight == Weight(pounds: 405, rounding: .nearest))
    }

    // MARK: - The draft's refusals (FR-1.13.3)

    @Test("A field holding nothing this locale reads as a number refuses")
    func anunreadableFieldRefuses() {
        var draft = TrainingMaxDraft(unit: .kilograms, locale: english, day: .now)
        #expect(draft.isBlank)
        #expect(draft.refusal == .notAWeight)
        draft.weightText = "180,5"
        #expect(draft.refusal == .notAWeight)
    }

    /// A negative figure is refused one step earlier, by the field's own parser — which is why the
    /// two refusals are not "zero" and "below zero".
    @Test("Zero is refused, since nothing is a percentage of it")
    func anonPositiveTrainingMaxRefuses() {
        var draft = TrainingMaxDraft(unit: .kilograms, locale: english, day: .now)
        draft.weightText = "0"
        #expect(draft.refusal == .notPositive)
        draft.weightText = "-180"
        #expect(draft.refusal == .notAWeight)
        draft.weightText = "180"
        #expect(draft.refusal == nil)
        #expect(draft.isSavable)
    }

    @Test("A note that is only whitespace is stored as no note at all")
    func awhitespaceNoteIsNoNote() {
        var draft = TrainingMaxDraft(unit: .kilograms, locale: english, day: .now)
        draft.reason = "   "
        #expect(draft.trimmedReason.isEmpty)
    }

    /// The locale the fields are read in. Pinned, on `G-3.4`'s rule: a suite that took the
    /// machine's would refuse `180.5` on a comma-decimal Mac.
    private var english: Locale { Locale(identifier: "en_US") }
}

/// A training-max repository that refuses, so a failed read and a failed write can be told apart.
///
/// Reads are optionally forwarded, which is what lets one test write against a store the section
/// has already read successfully — the case where the number stays on screen under the diagnostic.
private struct FailingTrainingMaxRepository: TrainingMaxRepository {
    /// Where a read is forwarded, or `nil` to refuse those too.
    var reads: (any TrainingMaxRepository)?

    /// What every refusal throws.
    private var failure: RepositoryError { .recordNotFound(id: UUID()) }

    func configuration(
        forExerciseID exerciseID: UUID,
        on date: Date
    ) async throws -> TrainingMaxEntry? {
        guard let reads else { throw failure }
        return try await reads.configuration(forExerciseID: exerciseID, on: date)
    }

    func configurationHistory(
        forExerciseID exerciseID: UUID,
        includingDeleted: Bool
    ) async throws -> [TrainingMaxEntry] {
        guard let reads else { throw failure }
        return try await reads.configurationHistory(
            forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }

    func saveConfiguration(_ entry: TrainingMaxEntry) async throws { throw failure }

    func trainingMax(
        forExerciseID exerciseID: UUID,
        on date: Date
    ) async throws -> TrainingMaxHistoryEntry? {
        guard let reads else { throw failure }
        return try await reads.trainingMax(forExerciseID: exerciseID, on: date)
    }

    func history(
        forExerciseID exerciseID: UUID,
        includingDeleted: Bool
    ) async throws -> [TrainingMaxHistoryEntry] {
        guard let reads else { throw failure }
        return try await reads.history(
            forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }

    func save(_ entry: TrainingMaxHistoryEntry) async throws { throw failure }

    func deleteEntry(id: UUID) async throws { throw failure }
}
