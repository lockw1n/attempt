import DerivedValues
import DesignSystem
import DesignTokens
import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// One past session — what was trained, what was lifted, and the corrections still allowed on it
/// (`FR-1.2.7`, `FR-1.2.9`).
///
/// **A `Logging` screen answering a History route.** `TR-1.3` keeps the two feature modules from
/// depending on each other, and everything this screen draws — the set row, the set editor, the note
/// section — is `Logging`'s; so the screen is built here and composed by the app target, exactly as
/// the gyms are for a Settings route and the exercise picker is for a Training one.
///
/// **What it offers is `FR-1.2.7` and nothing wider.** Editing and deleting a set are the two writes
/// the requirement names for a past session; adding one, reordering the exercises and `FR-1.2.5`'s
/// outcome control belong to the workout in progress and are absent here rather than dead. The
/// warmup flag is still correctable, because it is a field of the editor `FR-1.2.7` opens.
///
/// **The note is editable rather than read-only**, which is the same reading of the record: this
/// screen exists so a session can be corrected after the fact, and freezing the prose about it while
/// every set on it can be rewritten draws a line `FR-1.2.9` does not.
public struct PastSessionView: View {
    @State private var state: PastSessionState

    /// The modifier terms the set editor offers (`FR-1.2.8`).
    ///
    /// Held above this screen for `ActiveSessionView`'s reason (`TR-1.2`): the list outlives every
    /// screen that shows it, and a copy made per sheet would not see a term added in another.
    let vocabulary: SetModifierVocabulary

    /// The gym `FR-1.4.1`'s loading is worked out on, handed to the editor's row.
    let equipment: PlateCalculatorStore

    /// Which cards' warmup groups the user has unfolded by hand (`FR-1.2.14`), keyed on the entry.
    ///
    /// **Folded by default here, where the live screen folds them only once the work has started.**
    /// A past session's ramp is finished by definition, so the default is the same rule with its
    /// condition already met — see ``SessionExerciseList/defaultWarmupExpansion(for:)``.
    @State private var warmupExpansion: [UUID: Bool] = [:]

    /// Which set groups the user has opened (`FR-16.1.3`), keyed on the group — which is its first
    /// set's id.
    ///
    /// Collapsed by default, on ``SessionExerciseList/groupExpansion``'s rule and for its reason.
    @State private var groupExpansion: Set<UUID> = []

    /// Which set the editor is open over, or `nil` (`FR-1.2.7`).
    ///
    /// The screen's, and it carries no route, on `ActiveSessionView`'s argument: a half-corrected
    /// set is not a place in the app.
    @State private var editing: SetEditorTarget?

    /// What is in `FR-1.2.9`'s note field.
    ///
    /// The screen's rather than the state's, for `ActiveSessionView`'s reason: a note being typed is
    /// not a fact about the session until it is saved. It follows the record — see
    /// ``SessionNoteDraft/follow(_:)`` for what happens to an unsaved edit when one is re-read.
    @State private var noteDraft = SessionNoteDraft()

    /// Whether `FR-15.2.6`'s naming prompt is open.
    ///
    /// The screen's rather than the state's, on `noteDraft`'s rule: a name being typed is not a
    /// fact about anything until the command is confirmed.
    @State private var isNamingRoutine = false

    /// What that prompt's field holds.
    @State private var routineName = ""

    /// Which locale the day and the numbers are rendered for, and the editor parses in (`G-3.4`).
    @Environment(\.locale) private var locale

    /// Builds the screen over the session the route named and the repositories its state reads.
    ///
    /// - Parameters:
    ///   - sessionID: The session to show.
    ///   - workouts: The sessions, their entries and their sets.
    ///   - catalogue: The exercises those entries name.
    ///   - settings: The settings row, for the unit the loads are shown in.
    ///   - vocabulary: The modifier terms the set editor offers (`FR-1.2.8`).
    ///   - equipment: The gym the plate calculator loads against (`FR-1.4.1`).
    ///   - records: The app's one recompute actor (`TR-1.6`) — an edit here moves a personal record
    ///     as much as one made during the workout does.
    ///   - routines: Where `FR-15.2.6`'s routine is written.
    ///   - trainingMaxes: Where `FR-16.7.1`'s training max is stored, read at this session's day.
    public init(
        sessionID: UUID,
        workouts: any WorkoutRepository,
        catalogue: any ExerciseRepository,
        settings: any SettingsRepository,
        vocabulary: SetModifierVocabulary,
        equipment: PlateCalculatorStore,
        records: PersonalRecordRecomputer,
        routines: any RoutineRepository,
        trainingMaxes: any TrainingMaxRepository
    ) {
        _state = State(
            initialValue: PastSessionState(
                sessionID: sessionID,
                workouts: workouts,
                catalogue: catalogue,
                settings: settings,
                records: records,
                routines: routines,
                trainingMaxes: trainingMaxes))
        self.vocabulary = vocabulary
        self.equipment = equipment
    }

    /// The session, or whichever of the screen's other states is current.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl.points) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(title)
        // On every appearance, not once: this screen is returned to from the exercise detail
        // T-1.36 will link to, and the unit is changed in another tab.
        .task {
            await state.load()
            noteDraft.follow(holding: state.session)
        }
        // Every path that replaces the held record, the note's own save among them: the draft gives
        // way to what is stored only where the two already agreed. `holding:` and not `follow(_:)`
        // — a re-read passes through loading, and the gap is not the record going away. See
        // `SessionNoteDraft.follow(holding:)`.
        .onChange(of: state.phase) { noteDraft.follow(holding: state.session) }
        .sheet(item: $editing) { target in
            SetEditorSheet(
                draft: draft(for: target),
                isEditing: true,
                // No target: this screen has no planned-target read wired up, for the reason its
                // set rows draw none.
                unit: state.displayUnit,
                vocabulary: vocabulary,
                equipment: equipment,
                log: { write($0, target) },
                cancel: { editing = nil },
                delete: { delete(target) }
            )
            .presentationDetents([.medium, .large])
        }
        .alert(Text(LoggingStrings.saveRoutineTitle), isPresented: $isNamingRoutine) {
            // An alert rather than a screen, on the routine list's rename prompt's argument: one
            // field, two answers, and nothing to come back to.
            TextField(text: $routineName) { Text(LoggingStrings.saveRoutinePrompt) }
            Button(role: .cancel) {
                isNamingRoutine = false
            } label: {
                Text(LoggingStrings.saveRoutineCancel)
            }
            Button {
                saveAsRoutine()
            } label: {
                Text(LoggingStrings.saveRoutineConfirm)
            }
        }
    }

    /// The screen's five states (`FR-1.13.1`), each one of T-1.09's shared components.
    ///
    /// **"No such session" is an error state without a retry**, on `ExerciseDetailView`'s precedent
    /// for an identifier that resolves to nothing: the route was stored or shared, the row is gone,
    /// and reading again resolves to the same absence.
    ///
    /// **A read that failed is a different state and says a different thing**, with a retry. To the
    /// screen the two are the same absence; to the user one says the session is gone and the other
    /// says we could not tell.
    ///
    /// **No offline state**: a session is a local row (`G-2.1`, `G-2.3`), so there is no fetch to be
    /// offline for — the session list's argument. No insufficient-data state either: a session with
    /// nothing in it is empty, not short of data.
    @ViewBuilder private var content: some View {
        switch state.phase {
        case .idle, .loading:
            LoadingStateView()
        case .failed:
            ErrorStateView(
                headline: Text(LoggingStrings.pastSessionErrorHeadline),
                message: Text(LoggingStrings.pastSessionErrorMessage),
                retry: { Task { await state.load() } }
            )
        case .missing:
            ErrorStateView(
                headline: Text(LoggingStrings.pastSessionMissingHeadline),
                message: Text(LoggingStrings.pastSessionMissingMessage)
            )
        case .loaded:
            loaded
        }
    }

    /// A session that resolved: which week and day of a program it was, `FR-1.2.9`'s note, then
    /// its exercises.
    @ViewBuilder private var loaded: some View {
        programPosition
        SessionNotesSection(
            draft: $noteDraft,
            hasFailed: state.noteWriteFailure != nil,
            save: { Task { await state.saveNote(noteDraft.text) } }
        )
        // The banner describes one attempt to store one piece of text, so the next keystroke ends
        // it — including the one that puts the stored note back.
        .onChange(of: noteDraft.text) { state.noteWriteFailure = nil }
        exercises
        saveAsRoutineSection
    }

    /// Which week and day of a program this session was started from (`FR-16.8.3`, `DOD-16.1`).
    ///
    /// **Read off the session's own columns, which is the whole point of them**: before they
    /// existed a lifter following a plan had to type "W2D1" into the note, and that prose is what
    /// this line retires. Absent, not blank, on a workout started outside a program.
    ///
    /// **Above the note rather than in the title**, unlike the training day: the title is one line
    /// on a pushed screen and the day is already in it.
    @ViewBuilder private var programPosition: some View {
        if let position = state.session?.programPosition {
            Text(LoggingStrings.sessionProgramWeekAndDay(week: position.week, day: position.day))
                .font(Typography.metricContext.font)
                .foregroundStyle(ColorToken.textSecondary)
        }
    }

    /// `FR-15.2.6`'s command, at the foot of the screen and only where there is a workout to save.
    ///
    /// **Absent rather than disabled on a session with nothing logged in it**, which is the empty
    /// state's own reading: a workout that was started and never logged into prescribes nothing, and
    /// a routine built from it would be a list of nothing. Last on the screen for
    /// `ExerciseArchiveSection`'s reason — it is the one command here that is not about the session's
    /// own rows.
    @ViewBuilder private var saveAsRoutineSection: some View {
        if !state.exercises.isEmpty {
            SaveAsRoutineSection(outcome: state.saveAsRoutineOutcome) {
                routineName = ""
                isNamingRoutine = true
            }
        }
    }

    /// The session's exercises, or the empty state where it has none.
    ///
    /// **An empty state rather than a sentence**, unlike the live screen's per-card one: there a
    /// zero-set card sits among cards that are not empty, and here the whole screen is what has
    /// nothing on it. It offers no action — a past session is a record, and there is nothing to add
    /// to it from here.
    @ViewBuilder private var exercises: some View {
        if state.exercises.isEmpty {
            EmptyStateView(
                symbolName: "figure.strengthtraining.traditional",
                headline: Text(LoggingStrings.pastSessionEmptyHeadline),
                message: Text(LoggingStrings.pastSessionEmptyMessage)
            )
        } else {
            LazyVStack(alignment: .leading, spacing: Spacing.md.points) {
                ForEach(state.exercises) { item in
                    PastSessionExerciseCard(
                        item: item,
                        unit: state.displayUnit,
                        areWarmupsExpanded: warmupExpansion[item.id] ?? false,
                        toggleWarmups: {
                            warmupExpansion[item.id] = !(warmupExpansion[item.id] ?? false)
                        },
                        expandedGroups: groupExpansion,
                        toggleGroup: { setID in
                            if groupExpansion.contains(setID) {
                                groupExpansion.remove(setID)
                            } else {
                                groupExpansion.insert(setID)
                            }
                        },
                        edit: { editing = ActiveSessionView.target(editing: $0) }
                    )
                }
            }
            if state.writeFailure != nil {
                // Beneath the cards rather than in place of them: a failed write costs this screen
                // nothing, and the retry is the same correction attempted again.
                ErrorStateView(message: Text(LoggingStrings.pastSessionWriteErrorMessage))
            }
        }
    }

    /// The day this session belongs to, or a placeholder while there is none.
    ///
    /// **The date is the title**, because it is what identifies a past session — the live screen's
    /// title is a word because the workout in progress needs no identifying.
    private var title: Text {
        guard let session = state.session else { return Text(LoggingStrings.pastSessionTitle) }
        return Text(session.date, format: AppFormat.date(locale: locale))
    }

    /// The draft the editor opens holding — always `FR-1.2.7`'s set being edited, this screen having
    /// no way to add one.
    ///
    /// - Parameter target: What the editor is open over.
    /// - Returns: The draft.
    private func draft(for target: SetEditorTarget) -> SetDraft {
        guard let values = target.values else {
            return SetDraft(unit: state.displayUnit, locale: locale)
        }
        return SetDraft(editing: values, unit: state.displayUnit, locale: locale)
    }

    /// Writes what the confirmed editor decided and closes it (`FR-1.2.7`, `NFR-1.8`).
    ///
    /// **The sheet closes before the write is awaited**, on the live screen's rule: the write is
    /// local (`G-2.3`), so there is no window in which the row is visibly behind.
    ///
    /// A target that is not an edit, or a draft that does not resolve, writes nothing — the first
    /// this screen never produces, and the second the confirming command is disabled on.
    ///
    /// - Parameters:
    ///   - draft: What the user entered.
    ///   - target: What the editor was open over.
    private func write(_ draft: SetDraft, _ target: SetEditorTarget) {
        guard let setID = target.editing, let values = draft.resolved else { return }
        editing = nil
        Task { await state.editSet(id: setID, inEntryID: target.entryID, to: values) }
    }

    /// Writes this workout as a routine under the typed name and closes the prompt (`FR-15.2.6`).
    ///
    /// **The field is read before the prompt is dismissed**, the alert's own dismissal being what
    /// would otherwise race the read.
    private func saveAsRoutine() {
        let typed = routineName
        isNamingRoutine = false
        Task { await state.saveAsRoutine(named: typed) }
    }

    /// Soft-deletes the set the editor is open over and closes it (`FR-1.2.7`, `G-1.3`).
    ///
    /// - Parameter target: What the editor is open over.
    private func delete(_ target: SetEditorTarget) {
        guard let setID = target.editing else { return }
        editing = nil
        Task { await state.deleteSet(id: setID, inEntryID: target.entryID) }
    }
}

/// `FR-15.2.6`'s section: what it will build, the command, and what the last attempt did.
///
/// Taking the outcome and a closure rather than the state, on `ExerciseArchiveSection`'s rule:
/// this is what the snapshot renders, and every outcome has to be picturable without a store behind
/// it.
struct SaveAsRoutineSection: View {
    /// What the last attempt did, or `nil` where none has been made since the last read.
    let outcome: SaveAsRoutineOutcome?

    /// Opens the naming prompt.
    let save: () -> Void

    /// The explanation, the command, and the outcome beneath them.
    var body: some View {
        GroupedSection(Text(LoggingStrings.saveRoutineSection)) {
            Text(LoggingStrings.saveRoutineExplanation)
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textSecondary)
            Button(action: save) {
                Text(LoggingStrings.saveRoutineAction)
                    .font(Typography.actionLabel.font)
                    .foregroundStyle(ColorToken.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
                    .background(
                        ColorToken.surfaceRaised,
                        in: .rect(cornerRadius: CornerRadius.control.points)
                    )
            }
            .buttonStyle(.plain)
            report
        }
    }

    /// What the last attempt did, in whichever of its three shapes applies.
    ///
    /// **The success is a sentence rather than one of T-1.09's components**, there being no state
    /// component for a command that worked: nothing on this screen changed, so the confirmation is
    /// text and not a surface. The two failures are ``DesignSystem/ErrorStateView`` like every other
    /// refusal in this app, and neither carries a retry — the name is gone with the prompt, so the
    /// way back is the command itself.
    @ViewBuilder private var report: some View {
        switch outcome {
        case .saved(let name):
            Text(LoggingStrings.saveRoutineSaved(name))
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textSecondary)
        case .nameRequired:
            ErrorStateView(message: Text(LoggingStrings.saveRoutineNameRequired))
        case .writeFailed:
            ErrorStateView(message: Text(LoggingStrings.saveRoutineWriteError))
        case nil:
            EmptyView()
        }
    }
}
