import AppNavigation
import DerivedValues
import DesignSystem
import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// One exercise's detail (`FR-1.1.6`, `FR-1.1.7`).
///
/// The view half of `TR-1.2`'s pattern, and the same `ScrollView`/`LazyVStack` shape the list uses
/// for the same reason — `TR-1.12`'s harness renders through `ImageRenderer`, which draws a
/// placeholder for anything UIKit-backed, so a `List` here would snapshot as a grey box.
///
/// **All three of its derived sections now read for themselves**, each with its own store, its own
/// `.task` and its own states — so a value that cannot be computed costs the reader that section
/// and never `FR-1.1.6`'s movement, equipment and notes. The estimate's is also the screen's second
/// write: `FR-1.7.5`'s override is entered there.
public struct ExerciseDetailView: View {
    @State private var state: ExerciseDetailState

    /// The locale the screen resolves exercise names in (`FR-1.14.2`) — its title's, and the order
    /// its variations come in.
    @Environment(\.locale) private var locale

    /// Which exercise this screen is about — handed on to the history section, which reads for
    /// itself.
    private let exerciseID: UUID

    /// Where the history section's sets come from.
    private let workouts: any WorkoutRepository

    /// Where its display unit comes from — and the records section's.
    private let settings: any SettingsRepository

    /// The app's one recompute actor (`TR-1.6`), which the records section reads through.
    private let records: PersonalRecordRecomputer

    /// Builds the screen over the identifier the route carried.
    ///
    /// - Parameters:
    ///   - exerciseID: Which exercise to show.
    ///   - repository: Where it comes from. `Persistence`'s implementation in the app; anything
    ///     conforming in a test or a preview.
    ///   - workouts: Where the sets logged against it come from — a count for
    ///     ``ExerciseDetail/hasLoggedSets``, which the records section's copy turns on, and
    ///     `FR-1.5.2`'s history for the section that reads it properly.
    ///   - settings: The settings row, for the unit those loads are shown in (`G-3.1`).
    ///   - records: The app's one recompute actor (`TR-1.6`), for `FR-1.6.2`'s personal records — a
    ///     set logged in another tab moves one on this screen, which is what a shared actor buys.
    public init(
        exerciseID: UUID,
        repository: any ExerciseRepository,
        workouts: any WorkoutRepository,
        settings: any SettingsRepository,
        records: PersonalRecordRecomputer
    ) {
        self.exerciseID = exerciseID
        self.workouts = workouts
        self.settings = settings
        self.records = records
        _state = State(
            initialValue: ExerciseDetailState(
                exerciseID: exerciseID,
                repository: repository,
                workouts: workouts
            )
        )
    }

    /// The exercise's sections, or whichever of the screen's three other states is current.
    ///
    /// The title is the exercise's name, so it is `verbatim`: a row in a catalogue is data, not copy
    /// (`G-3.4`). It is empty until the read lands, which is what keeps a bar reading the last
    /// screen's name off the top of a loading one.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl.points) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(verbatim: title))
        .toolbar {
            if case .loaded(let detail) = state.phase {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(
                        value: Route.exerciseLibrary(.exerciseEdit(exerciseID: detail.exercise.id))
                    ) {
                        Text(ExerciseLibraryStrings.editAction)
                    }
                }
            }
        }
        // `refresh()`, not `load()`: an edit made above this screen has to be here on the way back
        // down (`FR-1.1.4`). See the method's own note.
        .task {
            state.nameLanguage = ExerciseNameLanguage(locale)
            await state.refresh()
        }
    }

    /// The name shown in the navigation bar, or nothing while there is no exercise.
    private var title: String {
        guard case .loaded(let detail) = state.phase else { return "" }
        return detail.exercise.displayName(for: locale)
    }

    /// The screen's four states (`FR-1.13.1`), each one of T-1.09's shared components.
    ///
    /// **No offline state, and no empty one, both deliberately.** The catalogue is local and
    /// bundle-seeded, so there is no fetch to be offline for (`G-2.1`, `NFR-1.7`) — the same
    /// argument the list makes. And this screen is about exactly one exercise: it either resolves or
    /// it does not, and the second of those is ``ExerciseDetailState/Phase/missing`` rather than an
    /// empty. `FR-1.13.3`'s insufficient-data state appears three times below — once as a section with
    /// nothing in it, and twice as one of a reading section's own four states.
    @ViewBuilder private var content: some View {
        switch state.phase {
        case .idle, .loading:
            LoadingStateView()
        case .failed:
            ErrorStateView(
                headline: Text(ExerciseLibraryStrings.detailErrorHeadline),
                message: Text(ExerciseLibraryStrings.detailErrorMessage),
                retry: { Task { await state.load() } }
            )
        case .missing:
            // No retry: the identifier resolved to nothing, and reading again resolves to nothing.
            ErrorStateView(
                headline: Text(ExerciseLibraryStrings.detailMissingHeadline),
                message: Text(ExerciseLibraryStrings.detailMissingMessage)
            )
        case .loaded(let detail):
            loaded(detail)
        }
    }

    /// The seven sections: the record's own fields, then the one thing here the user can change,
    /// then `FR-1.1.7`'s relationships, and `FR-1.1.6`'s three derived values — where they stay now
    /// that the first of them holds real data, since a screen opened to check a cue should not be
    /// scrolled past a training history to reach the notes.
    ///
    /// **`FR-1.1.5`'s archive control is last, below all of them.** It is the one command here that
    /// changes what the rest of the app shows, and the foot of a screen is where a command like that
    /// is reached deliberately rather than in passing.
    @ViewBuilder private func loaded(_ detail: ExerciseDetail) -> some View {
        ExerciseFactsSection(exercise: detail.exercise)
        ExerciseNotesSection(state: state)
        if detail.hasRelationships {
            ExerciseVariationsSection(parent: detail.parent, variations: detail.variations)
        }
        // The history reads for itself rather than off `detail`, and its heading is its own: it has
        // four states where a section with nothing in it has one, and a workout store that cannot
        // answer must not cost this screen the exercise. See `ExerciseHistorySection`.
        ExerciseHistorySection(exerciseID: exerciseID, workouts: workouts, settings: settings)
        // The records section reads for itself, and its heading is its own, on the history section's
        // rule: it has four states where a section with nothing in it has one. The set count is
        // still handed down, because it is what separates the two "nothing to show" sentences and
        // this screen is the only place it has already been read.
        //
        // THE ESTIMATE IS NOT ONE OF THE TWO, and that is deliberate. A 12-rep set, assisted work
        // and a set that targets ten and fails at eight each produce no estimate BY DESIGN, so a
        // user can have logged sets and still correctly have no e1RM — a count cannot tell those
        // apart from an exercise nothing has been logged against. The estimate's own section reads
        // the reason from the pipeline instead; see `ExerciseEstimateScreenState`.
        ExerciseRecordsSection(
            exerciseID: exerciseID,
            hasLoggedSets: detail.hasLoggedSets,
            records: records,
            settings: settings
        )
        ExerciseEstimateSection(exerciseID: exerciseID, records: records, settings: settings)
        ExerciseArchiveSection(
            isArchived: detail.exercise.isArchived,
            hasFailed: state.archiveFailure != nil
        ) {
            Task { await state.setArchived(!detail.exercise.isArchived) }
        }
    }
}

/// The exercise's own fields (`FR-1.1.6`).
///
/// Taking the record rather than the state, for the reason `ExerciseGroupList` does: this is what
/// the snapshot renders, and a reference over the whole screen would be a reference over a `.task`
/// that reads a store.
struct ExerciseFactsSection: View {
    /// The exercise these facts describe.
    let exercise: Exercise

    /// The archived badge where it applies, then one row per field.
    ///
    /// **The badge is here rather than beside the title** because the title is the navigation bar's,
    /// and an archived exercise is still reachable from logged history (`FR-1.1.5`) — without it the
    /// screen gives no reason for the exercise being absent from the list.
    var body: some View {
        GroupedSection(Text(ExerciseLibraryStrings.detailSection)) {
            if exercise.isArchived {
                Text(ExerciseLibraryStrings.detailArchivedBadge)
                    .font(Typography.metricLabel.font)
                    .foregroundStyle(ColorToken.textSecondary)
                    .padding(.horizontal, Spacing.sm.points)
                    .padding(.vertical, Spacing.xs.points)
                    .background(
                        ColorToken.surfaceRaised,
                        in: .rect(cornerRadius: CornerRadius.control.points)
                    )
            }
            ExerciseFactRow(
                label: ExerciseLibraryStrings.detailMovement,
                value: ExerciseLibraryStrings.label(for: exercise.movement)
            )
            ExerciseFactRow(
                label: ExerciseLibraryStrings.detailEquipment,
                value: ExerciseLibraryStrings.label(for: exercise.equipment)
            )
            ExerciseFactRow(
                label: ExerciseLibraryStrings.detailBar,
                value: ExerciseLibraryStrings.label(for: exercise.barType)
            )
            ExerciseFactRow(
                label: ExerciseLibraryStrings.detailLaterality,
                value: ExerciseLibraryStrings.label(for: exercise.laterality)
            )
            ExerciseFactRow(
                label: ExerciseLibraryStrings.detailOrigin,
                value: ExerciseLibraryStrings.label(
                    for: exercise.isCustom ? ExerciseOrigin.custom : .builtIn)
            )
        }
    }
}

/// One field: its name, then its value.
struct ExerciseFactRow: View {
    /// What the field is called.
    let label: LocalizedStringResource

    /// What this exercise's value for it is, built by the caller.
    let value: Text

    /// A field whose value is one of a vocabulary's names — copy, and localized (`G-3.4`).
    ///
    /// - Parameters:
    ///   - label: What the field is called.
    ///   - value: This exercise's value for it.
    init(label: LocalizedStringResource, value: LocalizedStringResource) {
        self.label = label
        self.value = Text(value)
    }

    /// A field whose value the caller has already built — the case a row of catalogue *data*, such
    /// as an exercise's name, needs, since that arrives `verbatim` rather than as copy.
    ///
    /// - Parameters:
    ///   - label: What the field is called.
    ///   - value: This exercise's value for it.
    init(label: LocalizedStringResource, value: Text) {
        self.label = label
        self.value = value
    }

    /// Side by side where both fit, stacked where they do not.
    ///
    /// `ViewThatFits` rather than a fixed `HStack`: at `NFR-1.10`'s ceiling the two halves do not
    /// share a 320-point line, and a label truncated to make room is a field with no name.
    ///
    /// The pair is one VoiceOver element (`G-4.2`) — "Movement, Squat" is one fact, and two stops
    /// per field over five fields is the failure mode.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md.points) {
                name
                Spacer(minLength: Spacing.sm.points)
                reading
            }
            VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                name
                reading
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The field's name.
    private var name: some View {
        Text(label)
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
    }

    /// The field's value.
    private var reading: some View {
        value
            .font(Typography.body.font)
            .foregroundStyle(ColorToken.textPrimary)
    }
}

/// The editable notes (`FR-1.1.6`), and the screen's only write.
struct ExerciseNotesSection: View {
    /// The state the field is bound to and the save runs through.
    @Bindable var state: ExerciseDetailState

    /// The field, the two commands that appear once it is dirty, and a failed write beneath them.
    ///
    /// **A `TextField(axis: .vertical)` rather than a `TextEditor`**: an editor has no intrinsic
    /// height and brings its own scroll view, which inside this screen's `ScrollView` is two scroll
    /// views arguing. The field grows with its content between the two line limits instead.
    ///
    /// The commands are hidden until there is something to commit, so a screen the user is only
    /// reading carries no buttons — and an unsaved edit is therefore visible as such.
    var body: some View {
        GroupedSection(Text(ExerciseLibraryStrings.notesSection)) {
            TextField(
                text: $state.notesDraft,
                prompt: Text(ExerciseLibraryStrings.notesPrompt),
                axis: .vertical
            ) {
                Text(ExerciseLibraryStrings.notesSection)
            }
            .labelsHidden()
            .lineLimit(3...10)
            .font(Typography.body.font)
            .foregroundStyle(ColorToken.textPrimary)
            .textFieldStyle(.plain)
            .padding(Spacing.md.points)
            .background(
                ColorToken.surfaceRaised,
                in: .rect(cornerRadius: CornerRadius.control.points)
            )

            if state.hasUnsavedNotes {
                commands
            }

            if state.writeFailure != nil {
                // The shared error component rather than a local label, and it keeps the draft on
                // screen beside it — `SettingsLandingState`'s rule that a failed write costs the
                // screen nothing.
                ErrorStateView(
                    message: Text(ExerciseLibraryStrings.notesError),
                    retry: { Task { await state.saveNotes() } }
                )
            }
        }
    }

    /// Save and discard, wrapping where they do not fit on one line.
    private var commands: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm.points) {
                save
                discard
            }
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                save
                discard
            }
        }
    }

    /// Commits the draft.
    private var save: some View {
        Button {
            Task { await state.saveNotes() }
        } label: {
            Text(ExerciseLibraryStrings.notesSave)
        }
        .buttonStyle(.primaryAction)
    }

    /// Puts the stored notes back.
    private var discard: some View {
        Button {
            state.discardNoteEdits()
        } label: {
            Text(ExerciseLibraryStrings.notesDiscard)
                .font(Typography.actionLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
                .frame(minHeight: TouchTarget.standard.points)
        }
        .buttonStyle(.plain)
    }
}

/// The variation relationships (`FR-1.1.7`), in both directions.
///
/// Shown only when there is at least one — see ``ExerciseDetail/hasRelationships``.
struct ExerciseVariationsSection: View {
    /// The exercise this one varies, if any.
    let parent: Exercise?

    /// The exercises that vary this one, in the order they are shown.
    let variations: [Exercise]

    /// The parent above the children, each row pushing that exercise's own detail.
    var body: some View {
        GroupedSection(Text(ExerciseLibraryStrings.variationsSection)) {
            if let parent {
                VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                    Text(ExerciseLibraryStrings.variationOf)
                        .font(Typography.metricLabel.font)
                        .foregroundStyle(ColorToken.textSecondary)
                    link(to: parent)
                }
            }
            ForEach(variations) { variation in
                link(to: variation)
            }
        }
    }

    /// One exercise, as a row that pushes its detail.
    private func link(to exercise: Exercise) -> some View {
        NavigationLink(value: Route.exerciseLibrary(.exerciseDetail(exerciseID: exercise.id))) {
            ExerciseRow(exercise: exercise)
        }
        .buttonStyle(.plain)
    }
}

/// `FR-1.1.5`'s archive control, in whichever of its two directions applies.
///
/// Taking the flag and a closure rather than the state, for the reason ``ExerciseFactsSection``
/// does: this is what the snapshot renders, and both directions have to be picturable without a
/// store behind them.
///
/// **No confirmation, deliberately.** Archiving hides an exercise and keeps everything logged with
/// it, and the reverse is the same button one tap later — a dialogue guarding a reversible action
/// that the sentence above already explains is a dialogue the user learns to dismiss.
struct ExerciseArchiveSection: View {
    /// Whether the exercise is archived now — which decides both the copy and what the button asks
    /// for.
    let isArchived: Bool

    /// Whether the last attempt failed. The exercise is unchanged when it did, so the button still
    /// asks for the same direction and the retry is the same command.
    let hasFailed: Bool

    /// Archives the exercise, or brings it back.
    let toggle: () -> Void

    /// What archiving does, the command, and a failed write beneath them.
    var body: some View {
        GroupedSection(Text(ExerciseLibraryStrings.archiveSection)) {
            Text(
                isArchived
                    ? ExerciseLibraryStrings.unarchiveExplanation
                    : ExerciseLibraryStrings.archiveExplanation
            )
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
            Button(action: toggle) {
                Text(
                    isArchived
                        ? ExerciseLibraryStrings.unarchiveAction
                        : ExerciseLibraryStrings.archiveAction
                )
                .font(Typography.actionLabel.font)
                .foregroundStyle(ColorToken.textPrimary)
                .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
                .background(
                    ColorToken.surfaceRaised,
                    in: .rect(cornerRadius: CornerRadius.control.points)
                )
            }
            .buttonStyle(.plain)
            if hasFailed {
                // The shared component rather than a local label, and the exercise stays on screen
                // beside it: nothing was stored, so the retry is another tap at the same command.
                ErrorStateView(
                    message: Text(ExerciseLibraryStrings.archiveError),
                    retry: toggle
                )
            }
        }
    }
}
