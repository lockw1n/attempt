import AppNavigation
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
/// **Three of its six sections have no data yet and say so** rather than being absent: history,
/// personal records and the current estimate each carry an ``DesignSystem/InsufficientDataView``
/// whose message names what would produce some (`FR-1.13.3`). The sections exist now so that
/// `T-1.36`, `T-1.41` and `T-1.43` change what is inside one rather than adding one.
public struct ExerciseDetailView: View {
    @State private var state: ExerciseDetailState

    /// Builds the screen over the identifier the route carried.
    ///
    /// - Parameters:
    ///   - exerciseID: Which exercise to show.
    ///   - repository: Where it comes from. `Persistence`'s implementation in the app; anything
    ///     conforming in a test or a preview.
    public init(exerciseID: UUID, repository: any ExerciseRepository) {
        _state = State(initialValue: ExerciseDetailState(exerciseID: exerciseID, repository: repository))
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
        .task { await state.load() }
    }

    /// The name shown in the navigation bar, or nothing while there is no exercise.
    private var title: String {
        guard case .loaded(let detail) = state.phase else { return "" }
        return detail.exercise.name
    }

    /// The screen's four states (`FR-1.13.1`), each one of T-1.09's shared components.
    ///
    /// **No offline state, and no empty one, both deliberately.** The catalogue is local and
    /// bundle-seeded, so there is no fetch to be offline for (`G-2.1`, `NFR-1.7`) — the same
    /// argument the list makes. And this screen is about exactly one exercise: it either resolves or
    /// it does not, and the second of those is ``ExerciseDetailState/Phase/missing`` rather than an
    /// empty. `FR-1.13.3`'s insufficient-data state appears three times below.
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

    /// The six sections: the record's own fields, then the one thing here the user can change,
    /// then `FR-1.1.7`'s relationships, and `FR-1.1.6`'s three derived values last — where they
    /// stay once they hold real data, since a screen opened to check a cue should not be scrolled
    /// past three charts to reach the notes.
    @ViewBuilder private func loaded(_ detail: ExerciseDetail) -> some View {
        ExerciseFactsSection(exercise: detail.exercise)
        ExerciseNotesSection(state: state)
        if detail.hasRelationships {
            ExerciseVariationsSection(parent: detail.parent, variations: detail.variations)
        }
        DerivedValueSection(
            title: ExerciseLibraryStrings.historySection,
            nothingYet: ExerciseLibraryStrings.historyNone
        )
        DerivedValueSection(
            title: ExerciseLibraryStrings.recordsSection,
            nothingYet: ExerciseLibraryStrings.recordsNone
        )
        DerivedValueSection(
            title: ExerciseLibraryStrings.e1rmSection,
            nothingYet: ExerciseLibraryStrings.e1rmNone
        )
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

    /// What this exercise's value for it is.
    let value: LocalizedStringResource

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
        Text(value)
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

/// A derived value that has nothing to show yet (`FR-1.13.3`).
///
/// One type for all three, because the difference between them is one string. The headline is the
/// component's own generic one: the section heading directly above already names what is missing,
/// and a second sentence saying it again is noise repeated three times down the screen.
struct DerivedValueSection: View {
    /// The section's heading.
    let title: LocalizedStringResource

    /// What would produce some data — the sentence `FR-1.13.3` requires in place of a blank.
    let nothingYet: LocalizedStringResource

    /// The heading, then the insufficient-data state under it.
    var body: some View {
        GroupedSection(Text(title)) {
            InsufficientDataView(message: Text(nothingYet))
        }
    }
}
