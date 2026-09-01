import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// What the editor is open over, and what confirming it writes (`FR-1.2.3`, `FR-1.2.7`).
///
/// **The screen's own branch, answered without a screen.** Which write a confirmed form resolves to
/// is the single place adding and editing part company, and both ways of getting it wrong are
/// invisible below this layer — an edit taken as an add appends a duplicate set, and an edit opened
/// as a duplicate erases the note on the next confirm. Each is a perfectly ordinary write by the
/// time the store sees it.
@Suite("The set editor's target and its write")
struct SetEditorWriteTests {
    /// The set every test here points the editor at.
    private static let values = SetEntryValues(
        weight: Weight(grams: 102_500), reps: 5, rpe: 8, isWarmup: false, notes: "belt on")

    @Test("An edit is identified by the set, and an addition by the exercise")
    func aTargetIsIdentifiedByWhatItIsFor() {
        let entryID = UUID()
        let setID = UUID()

        let adding = SetEditorTarget(entryID: entryID, values: Self.values)
        let editing = SetEditorTarget(entryID: entryID, values: Self.values, editing: setID)
        let another = SetEditorTarget(entryID: entryID, values: Self.values, editing: UUID())

        // Two drafts against one exercise are the same sheet, which is what re-presents it when the
        // user closes it and taps another card.
        #expect(adding.id == entryID)
        // Two sets on one card are two different edits: keyed on the entry, the second would
        // re-present the first one's form.
        #expect(editing.id == setID)
        #expect(editing.id != another.id)
        #expect(editing.id != adding.id)
    }

    @Test("An edit opens carrying the note, an addition of a copy does not, and a blank one is blank")
    func aTargetDecidesWhichDraftTheFormOpensOn() {
        let entryID = UUID()

        let edited = ActiveSessionView.draft(
            for: SetEditorTarget(entryID: entryID, values: Self.values, editing: UUID()),
            unit: .kilograms,
            locale: .posix
        )
        let repeated = ActiveSessionView.draft(
            for: SetEditorTarget(entryID: entryID, values: Self.values),
            unit: .kilograms,
            locale: .posix
        )
        let blank = ActiveSessionView.draft(
            for: SetEditorTarget(entryID: entryID), unit: .kilograms, locale: .posix)

        #expect(edited.notes == "belt on")
        #expect(repeated.notes.isEmpty)
        #expect(blank.isBlank)
        // The other four fields are the duplicate's either way — only the note separates them.
        #expect(edited.weightText == repeated.weightText)
        #expect(edited.repsText == repeated.repsText)
    }

    /// `FR-15.2.3`'s pre-fill, and `FR-15.2.2`'s blank target inside it: the plan is the third way
    /// a form opens filled in, and the only one whose load can be missing.
    @Test("A planned target opens the form filled in, and a blank-weight one still fills the reps")
    func aPlannedTargetOpensTheFormFilledIn() {
        let entryID = UUID()

        let planned = ActiveSessionView.draft(
            for: SetEditorTarget(
                entryID: entryID, planned: PlannedSetSeed(weight: Weight(grams: 100_000), reps: 5)),
            unit: .kilograms,
            locale: .posix
        )
        let blankWeight = ActiveSessionView.draft(
            for: SetEditorTarget(entryID: entryID, planned: PlannedSetSeed(weight: nil, reps: 8)),
            unit: .kilograms,
            locale: .posix
        )

        #expect(planned.weightText == "100")
        #expect(planned.repsText == "5")
        // The load is the one thing the blank plan left open. The reps are not: a form that opened
        // wholly blank here would be `NFR-15.3`'s two taps plus a keyboard.
        #expect(blankWeight.weightText.isEmpty)
        #expect(blankWeight.repsText == "8")
        // A plan prescribes the work, so neither seeds a warmup or a note.
        #expect(planned.isWarmup == false)
        #expect(planned.notes.isEmpty)
    }

    /// `FR-15.3.1` on the form the sheet covers the card with: the prescription is carried so the
    /// editor can draw it, and it seeds nothing — an edit opens holding the set as it was logged.
    @Test("An edited set carries its prescription without the plan seeding the form")
    func anEditCarriesItsPrescription() {
        let group = PlannedTargetGroup(
            id: UUID(),
            createdAt: .distantPast,
            updatedAt: .distantPast,
            deletedAt: nil,
            exerciseEntryID: UUID(),
            order: 0,
            targetWeight: Weight(grams: 100_000),
            targetReps: 5,
            targetSets: 3
        )
        let set = SetEntry(
            id: UUID(),
            createdAt: .distantPast,
            updatedAt: .distantPast,
            deletedAt: nil,
            entryID: UUID(),
            order: 0,
            weight: Weight(grams: 97_500),
            reps: 4,
            rpe: nil,
            rir: nil,
            isWarmup: false,
            isCompleted: true,
            targetWeight: nil,
            targetReps: nil,
            modifiers: [],
            notes: "",
            completedAt: nil
        )

        let target = ActiveSessionView.target(editing: set, prescribed: group)
        let draft = ActiveSessionView.draft(for: target, unit: .kilograms, locale: .posix)

        #expect(target.prescribed == group)
        #expect(target.planned == nil)
        // What the lifter did, not what was asked for: a plan that seeded here would overwrite the
        // set being corrected with the prescription it deviated from.
        #expect(draft.weightText == "97.5")
        #expect(draft.repsText == "4")
    }

    @Test("A target carrying a set rewrites that set, and one without logs a new one")
    func aTargetDecidesWhichWriteConfirmingIt() {
        let entryID = UUID()
        let setID = UUID()
        let draft = SetDraft(editing: Self.values, unit: .kilograms, locale: .posix)

        let rewrite = ActiveSessionView.write(
            draft, over: SetEditorTarget(entryID: entryID, values: Self.values, editing: setID))
        let addition = ActiveSessionView.write(
            draft, over: SetEditorTarget(entryID: entryID, values: Self.values))

        #expect(rewrite == .rewrite(setID: setID, entryID: entryID, values: Self.values))
        #expect(addition == .add(entryID: entryID, values: Self.values))
    }

    @Test("A draft that does not resolve writes nothing, either way")
    func anUnresolvableDraftWritesNothing() {
        // The confirming command is disabled in this state, so this is the second reading of a
        // guard the editor already applies — and the one a caller cannot skip.
        var draft = SetDraft(editing: Self.values, unit: .kilograms, locale: .posix)
        draft.weightText = "heavy"

        #expect(ActiveSessionView.write(draft, over: SetEditorTarget(entryID: UUID())) == nil)
        #expect(
            ActiveSessionView.write(
                draft, over: SetEditorTarget(entryID: UUID(), editing: UUID())) == nil)
    }

    @Test("The store performs both, and a rewrite never appends")
    func theStorePerformsWhatWasDecided() async throws {
        let workout = try await Workout.started()
        let logged = try await workout.logSet(
            SetEntryValues(
                weight: Weight(grams: 100_000), reps: 5, rpe: nil, isWarmup: false, notes: ""))

        await workout.store.write(
            .rewrite(setID: logged.id, entryID: logged.entryID, values: Self.values))

        // Rewritten where it sat: one set, still the same row.
        let rewritten = try #require(workout.store.exercises.first?.sets)
        #expect(rewritten.count == 1)
        #expect(rewritten.first?.id == logged.id)
        #expect(rewritten.first?.weight == Weight(grams: 102_500))
        #expect(rewritten.first?.notes == "belt on")

        await workout.store.write(
            .add(
                entryID: logged.entryID,
                values: SetEntryValues(
                    weight: Weight(grams: 60_000), reps: 8, rpe: nil, isWarmup: true, notes: "")))

        let both = try #require(workout.store.exercises.first?.sets)
        #expect(both.count == 2)
        #expect(both.last?.id != logged.id)
        #expect(both.last?.weight == Weight(grams: 60_000))
    }
}

/// What both writes do when the repository refuses them (`FR-1.2.7`, `FR-1.13.1`).
///
/// **A scripted repository rather than the faithful fake, and that is what the two paths cost.**
/// Both look the set up before they write and answer "nothing to write" when it is missing, so a
/// repository that answers reads honestly is one neither of them can fail against — the branch that
/// reports a failure is unreachable through the in-memory stack by construction. The scripted
/// double refuses every set call, which is what makes it reachable at all.
@Suite("A repository that refuses the write")
struct RefusedSetEditingTests {
    /// What the tests try to write.
    private static let values = SetEntryValues(
        weight: Weight(grams: 102_500), reps: 5, rpe: 8, isWarmup: false, notes: "")

    @Test("Both calls propagate what the repository throws")
    func theWriterPropagates() async throws {
        let scripted = ScriptedWorkoutRepository(row: .fixture())
        let writer = LoggedSetWriter(
            repository: scripted,
            records: PersonalRecordRecomputer(
                workouts: scripted,
                exercises: InMemoryRepositoryStack().exercises,
                cache: InMemoryRepositoryStack().personalRecords))

        await #expect(throws: RepositoryError.self) {
            try await writer.edit(id: UUID(), inEntryID: UUID(), to: Self.values)
        }
        await #expect(throws: RepositoryError.self) {
            try await writer.delete(id: UUID(), inEntryID: UUID())
        }
    }

    @Test("The store reports a refused edit as a failed write")
    func theStoreReportsARefusedEdit() async throws {
        let store = try await Self.storeOverARefusingRepository()

        await store.editSet(id: UUID(), inEntryID: UUID(), to: Self.values)

        let failure = try #require(store.exercisesWriteFailure)
        #expect(failure.contains("recordNotFound"))
    }

    @Test("And a refused deletion the same way")
    func theStoreReportsARefusedDelete() async throws {
        let store = try await Self.storeOverARefusingRepository()

        await store.deleteSet(id: UUID(), inEntryID: UUID())

        let failure = try #require(store.exercisesWriteFailure)
        #expect(failure.contains("recordNotFound"))
    }

    @Test("A confirmed form carries the modifiers it was opened with, unrecognised ones included")
    func theWriteCarriesTheModifiers() throws {
        let entryID = UUID()
        let setID = UUID()
        let carried = [SetModifier(.belt), SetModifier(rawValue: "chains")]
        var draft = SetDraft(unit: .kilograms, locale: .posix)
        draft.weightText = "102.5"
        draft.repsText = "5"
        draft.modifiers = carried

        let added = try #require(
            ActiveSessionView.write(draft, over: SetEditorTarget(entryID: entryID)))
        let rewritten = try #require(
            ActiveSessionView.write(
                draft, over: SetEditorTarget(entryID: entryID, editing: setID)))

        guard case .add(_, let addedValues) = added,
            case .rewrite(_, _, let rewrittenValues) = rewritten
        else {
            Issue.record("the form resolved to neither kind of write")
            return
        }
        // `FR-1.2.8` reaching the write path: before this task the column was carried across from
        // the stored row, so a picked modifier had nowhere to go and a removed one could not go.
        #expect(addedValues.modifiers == carried)
        #expect(rewrittenValues.modifiers == carried)
        // The unrecognised spelling is the one that matters — see `OpenVocabulary`.
        #expect(addedValues.modifiers.last?.rawValue == "chains")
    }

    @Test("A form the user cleared writes no modifiers, which is what takes one off a set")
    func theWriteCanClearTheModifiers() throws {
        var draft = SetDraft(
            editing: SetEntryValues(
                weight: Weight(grams: 100_000),
                reps: 5,
                rpe: nil,
                isWarmup: false,
                modifiers: [SetModifier(.belt)]
            ),
            unit: .kilograms,
            locale: .posix
        )
        draft.modifiers = []

        let write = try #require(
            ActiveSessionView.write(
                draft, over: SetEditorTarget(entryID: UUID(), editing: UUID())))

        guard case .rewrite(_, _, let values) = write else {
            Issue.record("an edit resolved to an addition")
            return
        }
        #expect(values.modifiers.isEmpty)
    }

    /// A store holding a workout, over a repository that refuses every call about a set.
    ///
    /// - Returns: The store.
    private static func storeOverARefusingRepository() async throws -> ActiveSessionStore {
        let session = WorkoutSession.fixture()
        let store = ActiveSessionStore.overWorkouts(ScriptedWorkoutRepository(row: session))
        await store.adopt(sessionID: session.id)
        // The session guard is what both writes check first, so a store that never adopted one
        // would return before reaching the repository and pass this suite for the wrong reason.
        #expect(store.session != nil)
        return store
    }
}
