import DesignSystem
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
    public init(
        sessionID: UUID,
        workouts: any WorkoutRepository,
        catalogue: any ExerciseRepository,
        settings: any SettingsRepository,
        vocabulary: SetModifierVocabulary,
        equipment: PlateCalculatorStore
    ) {
        _state = State(
            initialValue: PastSessionState(
                sessionID: sessionID, workouts: workouts, catalogue: catalogue, settings: settings))
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
            noteDraft.follow(session)
        }
        // Every path that replaces the held record, the note's own save among them: the draft gives
        // way to what is stored only where the two already agreed.
        .onChange(of: state.phase) { noteDraft.follow(session) }
        .sheet(item: $editing) { target in
            SetEditorSheet(
                draft: draft(for: target),
                isEditing: true,
                vocabulary: vocabulary,
                equipment: equipment,
                log: { write($0, target) },
                cancel: { editing = nil },
                delete: { delete(target) }
            )
            .presentationDetents([.medium, .large])
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

    /// A session that resolved: `FR-1.2.9`'s note, then its exercises.
    @ViewBuilder private var loaded: some View {
        SessionNotesSection(
            draft: $noteDraft,
            hasFailed: state.noteWriteFailure != nil,
            save: { Task { await state.saveNote(noteDraft.text) } }
        )
        // The banner describes one attempt to store one piece of text, so the next keystroke ends
        // it — including the one that puts the stored note back.
        .onChange(of: noteDraft.text) { state.noteWriteFailure = nil }
        exercises
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

    /// The session the state resolved to, or `nil`.
    private var session: WorkoutSession? {
        guard case .loaded(let session) = state.phase else { return nil }
        return session
    }

    /// The day this session belongs to, or a placeholder while there is none.
    ///
    /// **The date is the title**, because it is what identifies a past session — the live screen's
    /// title is a word because the workout in progress needs no identifying.
    private var title: Text {
        guard let session else { return Text(LoggingStrings.pastSessionTitle) }
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

    /// Soft-deletes the set the editor is open over and closes it (`FR-1.2.7`, `G-1.3`).
    ///
    /// - Parameter target: What the editor is open over.
    private func delete(_ target: SetEditorTarget) {
        guard let setID = target.editing else { return }
        editing = nil
        Task { await state.deleteSet(id: setID, inEntryID: target.entryID) }
    }
}

/// One exercise as it was performed, in a session that is over.
///
/// **The live card's contents without its commands.** `SessionExerciseCard` carries `FR-1.2.2`'s
/// reorder, `FR-1.2.6`'s repeat and `FR-1.2.3`'s add — three things a past session does not offer —
/// and `FR-1.2.13`'s fold, which exists so a lifter mid-workout can get past what they have already
/// done. What is shared is the part that matters: ``SetRow`` and ``SetNumbering``, so a set reads
/// identically wherever it is drawn.
///
/// Taking the exercise and the unit rather than the state, so a reference can render it without a
/// repository behind it.
struct PastSessionExerciseCard: View {
    /// The exercise, its entry and its sets.
    let item: SessionExercise

    /// The unit this card's loads are shown in (`G-3.1`).
    let unit: MassUnit

    /// Whether this card's warmup group is open (`FR-1.2.14`).
    let areWarmupsExpanded: Bool

    /// Opens or closes it.
    let toggleWarmups: () -> Void

    /// Opens `FR-1.2.7`'s editor over one of this card's sets.
    let edit: (SetEntry) -> Void

    /// The exercise's name, then its sets.
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                name
                    .font(Typography.cardTitle.font)
                    .foregroundStyle(ColorToken.textPrimary)
                if item.sets.isEmpty {
                    // The set list's own copy, shared with the live card because it is one component
                    // drawn on two screens rather than two screens saying the same thing.
                    Text(LoggingStrings.setListEmpty)
                        .font(Typography.body.font)
                        .foregroundStyle(ColorToken.textSecondary)
                } else {
                    warmupGroup
                    ForEach(workingSets) { row(for: $0) }
                }
            }
        }
    }

    /// `FR-1.2.14`'s warmups, folded by default: see ``PastSessionView/warmupExpansion``.
    @ViewBuilder private var warmupGroup: some View {
        if !warmups.isEmpty {
            WarmupSectionHeader(
                count: warmups.count, isExpanded: areWarmupsExpanded, toggle: toggleWarmups)
            if areWarmupsExpanded {
                ForEach(warmups) { row(for: $0) }
            }
        }
    }

    /// One set's row, with the two marking controls absent — see ``SetRow/mark``.
    ///
    /// - Parameter numbered: The set and its number.
    /// - Returns: The row.
    private func row(for numbered: NumberedSet) -> some View {
        SetRow(numbered: numbered, unit: unit, mark: nil, markCompleted: nil, edit: edit)
    }

    /// This card's sets, each carrying its number within its own sequence (`FR-1.2.14`).
    private var numberedSets: [NumberedSet] { SetNumbering.numbered(item.sets) }

    /// The warmups among them, in the order they were logged.
    private var warmups: [NumberedSet] { numberedSets.filter(\.isWarmup) }

    /// The work proper, likewise.
    private var workingSets: [NumberedSet] { numberedSets.filter { !$0.isWarmup } }

    /// The exercise's name, or a sentence in place of one — see ``SessionExercise/exercise``.
    private var name: Text {
        guard let exercise = item.exercise else {
            return Text(LoggingStrings.sessionExerciseMissing)
        }
        return Text(verbatim: exercise.name)
    }
}
