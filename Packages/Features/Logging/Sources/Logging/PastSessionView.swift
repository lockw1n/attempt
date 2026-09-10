import DerivedValues
import DesignSystem
import DesignTokens
import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// One past session — what was trained, what was lifted, and the corrections still allowed on it
/// (`FR-1.2.7`, `FR-1.2.9`, `FR-17.7`).
///
/// **A `Logging` screen answering a History route.** `TR-1.3` keeps the two feature modules from
/// depending on each other, and everything this screen draws — the set row, the checklist row, the
/// set editor, the note field — is `Logging`'s; so the screen is built here and composed by the app
/// target, exactly as the gyms are for a Settings route and the exercise picker is for a Training
/// one.
///
/// **Two shapes, and the session's stamp chooses** (`FR-17.7.6`). A workout that was a day of a
/// program is drawn as the checklist draws it — ``DayExerciseRow`` over ``DayRow``, one line per
/// exercise, a skipped row reading **Skipped** — because a lifter who answered a checklist should
/// be shown the same list back. A free workout keeps the cards it has always had: it was logged set
/// by set, and there is no plan to check it against.
///
/// **What it offers is `FR-1.2.7` and `FR-17.7.5`, and nothing wider.** On a day, **Log** reopens
/// the sheet over an answered row and rewrites it; there is no circle, no skip and no way to add an
/// exercise, because those are how a day is *answered* and this one has been. On a free workout,
/// editing and deleting a set are the two writes as before. `FR-1.2.5`'s outcome control belongs to
/// the workout in progress and is absent rather than dead.
///
/// **The note is editable rather than read-only**, which is the same reading of the record: this
/// screen exists so a session can be corrected after the fact, and freezing the prose about it while
/// every set on it can be rewritten draws a line `FR-1.2.9` does not. It is folded at the foot now
/// (`FR-17.7.1`), where the active session's is.
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

    /// Which set the free workout's editor is open over, or `nil` (`FR-1.2.7`).
    ///
    /// The screen's, and it carries no route, on `ActiveSessionView`'s argument: a half-corrected
    /// set is not a place in the app.
    @State private var editing: SetEditorTarget?

    /// Which row the day's Log sheet is open over, or `nil` (`FR-17.7.5`).
    ///
    /// **A second piece of state rather than a wider first one**, because the two sheets are two
    /// forms over two things: one is a set, the other is a whole exercise's answer, and a screen
    /// that is one shape or the other can never have both open.
    @State private var logging: DayLogTarget?

    /// What is in `FR-1.2.9`'s note field.
    ///
    /// The screen's rather than the state's, for `ActiveSessionView`'s reason: a note being typed is
    /// not a fact about the session until it is saved. It follows the record — see
    /// ``SessionNoteDraft/follow(_:)`` for what happens to an unsaved edit when one is re-read.
    @State private var noteDraft = SessionNoteDraft()

    /// Whether the note's fold is open (`FR-17.7.1`).
    ///
    /// The screen's and stored nowhere, on ``SessionNotesFold/isExpanded``'s rule: a session
    /// reopened tomorrow starts folded like one opened for the first time.
    @State private var areNotesExpanded = false

    /// Which locale the day and the numbers are rendered for, and the editor parses in (`G-3.4`).
    @Environment(\.locale) private var locale

    /// Builds the screen over the session the route named and the repositories its state reads.
    ///
    /// - Parameters:
    ///   - sessionID: The session to show.
    ///   - workouts: The sessions, their entries, their sets and their planned targets.
    ///   - catalogue: The exercises those entries name.
    ///   - settings: The settings row, for the unit the loads are shown in.
    ///   - vocabulary: The modifier terms the set editor offers (`FR-1.2.8`).
    ///   - equipment: The gym the plate calculator loads against (`FR-1.4.1`).
    ///   - records: The app's one recompute actor (`TR-1.6`) — an edit here moves a personal record
    ///     as much as one made during the workout does, and the same cache is what `FR-17.7.2`'s
    ///     badge is read from.
    ///   - trainingMaxes: Where `FR-16.7.1`'s training max is stored, read at this session's day.
    public init(
        sessionID: UUID,
        workouts: any WorkoutRepository & PlannedTargetRepository,
        catalogue: any ExerciseRepository,
        settings: any SettingsRepository,
        vocabulary: SetModifierVocabulary,
        equipment: PlateCalculatorStore,
        records: PersonalRecordRecomputer,
        trainingMaxes: any TrainingMaxRepository
    ) {
        _state = State(
            initialValue: PastSessionState(
                sessionID: sessionID,
                workouts: workouts,
                catalogue: catalogue,
                settings: settings,
                records: records,
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
                mode: .set(isEditing: true),
                // No target: a free workout's rows draw none, for the reason its card gives.
                unit: state.displayUnit,
                vocabulary: vocabulary,
                equipment: equipment,
                log: { write($0, target) },
                cancel: { editing = nil },
                delete: { delete(target) }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $logging) { target in
            SetEditorSheet(
                draft: ActiveSessionView.draft(
                    for: target.editorTarget, unit: state.displayUnit, locale: locale),
                mode: .row(target.row),
                prescribed: target.prescribed,
                unit: state.displayUnit,
                vocabulary: vocabulary,
                equipment: equipment,
                log: { draft in
                    guard let group = draft.resolvedGroup else { return }
                    let rowID = target.rowID
                    logging = nil
                    Task { await state.log(rowID: rowID, group: group) }
                },
                cancel: { logging = nil }
                // No **Skip this exercise**: skipping is how a day is answered while it is being
                // answered (`FR-17.9.6`), and this one has been. What is left is the correction.
            )
            // `.large`, for `DayView`'s measured reason — the same sheet, so the same detent.
            .presentationDetents([.large])
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
                retryEmphasis: .primary,
                retry: { Task { await state.load() } }
            )
        case .missing:
            ErrorStateView(
                headline: Text(LoggingStrings.pastSessionMissingHeadline),
                message: Text(LoggingStrings.pastSessionMissingMessage)
            )
        case .loaded(let session):
            loaded(session)
        }
    }

    /// A session that resolved: its own facts, then its exercises, then `FR-1.2.9`'s note.
    ///
    /// **The note is last** (`FR-17.7.1`), which is where the active session puts it and for the
    /// same reason: it is written once, at the end, and an editor above the first exercise cost
    /// this screen 149 pt of the thing it exists to show (review finding 13).
    ///
    /// - Parameter session: The record.
    /// - Returns: The screen.
    @ViewBuilder private func loaded(_ session: WorkoutSession) -> some View {
        SessionSummaryLine(session: session, adherence: state.adherence)
        exercises
        SessionNotesFold(
            draft: $noteDraft,
            isExpanded: $areNotesExpanded,
            hasFailed: state.noteWriteFailure != nil,
            // This screen's one filled accent (`FR-16.6.4`): unlike the active session there is no
            // **Finish workout** under the fold, and this is the one thing here that commits.
            saveEmphasis: .primary,
            save: { Task { await state.saveNote(noteDraft.text) } }
        )
        // The banner describes one attempt to store one piece of text, so the next keystroke ends
        // it — including the one that puts the stored note back.
        .onChange(of: noteDraft.text) { state.noteWriteFailure = nil }
    }

    /// The session's exercises in whichever of the two shapes it has, or the empty state.
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
            if state.isPlannedDay {
                dayRows
            } else {
                cards
            }
            if state.writeFailure != nil {
                // Beneath the rows rather than in place of them: a failed write costs this screen
                // nothing, and the retry is the same correction attempted again.
                ErrorStateView(message: Text(LoggingStrings.pastSessionWriteErrorMessage))
            }
        }
    }

    /// A past planned day (`FR-17.7.6`) — the checklist's own section, read-only but for **Log**.
    ///
    /// **``DayChecklistSection`` rather than the rows assembled here**, which is T-16.17's rule: the
    /// heading, the grouping and what each row offers are decisions, and a screen that restated them
    /// would be a second place they live. `answer` and `skip` are absent, which is the whole of what
    /// read-only means — see ``DayExerciseRow/answer``.
    @ViewBuilder private var dayRows: some View {
        DayChecklistSection(
            rows: state.dayRows,
            progress: DayProgress(state.dayRows),
            unit: state.displayUnit,
            log: { rowID in open(rowID) })
    }

    /// A past free workout — the cards it has always had.
    @ViewBuilder private var cards: some View {
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
                    edit: { editing = ActiveSessionView.target(editing: $0) },
                    recordMarks: { state.personalRecords.marks(forSetID: $0) },
                    isSessionOpen: state.session?.isFinished == false
                )
            }
        }
    }

    /// The day this session belongs to, or a placeholder while there is none.
    ///
    /// **The date is the title**, because it is what identifies a past session — the live screen's
    /// title is a word because the workout in progress needs no identifying. The program position
    /// and the adherence are on ``SessionSummaryLine`` beneath it (`FR-17.7.6`), where the active
    /// session draws the same two facts.
    private var title: Text {
        guard let session = state.session else { return Text(LoggingStrings.pastSessionTitle) }
        return Text(session.date, format: AppFormat.date(locale: locale))
    }

    /// Opens the Log sheet over one of a past day's rows (`FR-17.7.5`).
    ///
    /// A row the screen no longer holds opens nothing, on `DayView`'s rule: it went away underneath
    /// the list.
    ///
    /// - Parameter rowID: The row — an entry, on this screen.
    private func open(_ rowID: UUID) {
        guard let row = state.editorRow(forRow: rowID) else { return }
        // No pinned plan line: the sheet's row mode draws none (`OUT-17.8`), so the group is
        // carried for the shape's sake and read by nothing here.
        logging = DayLogTarget(rowID: rowID, row: row, prescribed: nil)
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
