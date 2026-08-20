import AppNavigation
import DesignSystem
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// The exercise library's list (`FR-1.1.1`, `FR-1.1.2`).
///
/// The view half of `TR-1.2`'s pattern: it holds ``ExerciseListState`` in `@State`, reads its phase
/// and derived groups, and decides nothing a test would want to ask about.
///
/// **A `ScrollView` and a `LazyVStack`, not a `List`.** Two reasons, and the first is the binding
/// one: `TR-1.12`'s harness renders through `ImageRenderer`, which draws a placeholder for anything
/// UIKit-backed — a `List` screen snapshots as a grey box and the gate would be measuring nothing.
/// The second is that a card-and-heading layout is `GroupedSection`'s, and a `List` would bring its
/// own insets and separators to argue with it.
public struct ExerciseListView: View {
    @State private var state: ExerciseListState

    /// The shell's navigation position, for the one command here that is not a `NavigationLink`.
    ///
    /// **Optional, and read rather than required**: a `StateAction` is a closure, so the empty
    /// state's way into the create form has to push a `Route` itself. A preview or a snapshot has no
    /// shell above it, and a screen that trapped on that would be a screen the harness cannot
    /// render.
    @Environment(NavigationState.self) private var navigation: NavigationState?

    /// Builds the screen over the repository its state reads through.
    ///
    /// - Parameter repository: Where the catalogue comes from. `Persistence`'s implementation in the
    ///   app; anything conforming in a test or a preview.
    public init(repository: any ExerciseRepository) {
        _state = State(initialValue: ExerciseListState(repository: repository))
    }

    /// The search field, the filters, and whichever of the screen's four states is current.
    ///
    /// `.searchable` rather than a `TextField`: it is the system's search affordance, it is placed
    /// by the enclosing `NavigationStack`, and it keeps a UIKit-backed control out of the body that
    /// the snapshot renders.
    public var body: some View {
        @Bindable var state = state
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg.points) {
                ExerciseFilterBar(state: state)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(ExerciseLibraryStrings.title))
        .searchable(text: $state.searchText, prompt: Text(ExerciseLibraryStrings.searchPrompt))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: Route.exerciseLibrary(.exerciseCreate)) {
                    Label {
                        Text(ExerciseLibraryStrings.createAction)
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        // `refresh()`, not `load()`: an exercise created or edited above this screen has to be here
        // on the way back down (`FR-1.1.3`, `FR-1.1.4`). See the method's own note.
        .task { await state.refresh() }
    }

    /// The screen's four states (`FR-1.13.1`), each one of T-1.09's shared components.
    ///
    /// **No offline state, and that is a decision rather than an omission**: the catalogue is local
    /// and is seeded from the app bundle, so there is no fetch to be offline for (`G-2.1`,
    /// `NFR-1.7`). No insufficient-data state either — nothing on this screen is derived.
    @ViewBuilder private var content: some View {
        switch state.phase {
        case .idle, .loading:
            LoadingStateView()
        case .failed:
            ErrorStateView(
                headline: Text(ExerciseLibraryStrings.errorHeadline),
                message: Text(ExerciseLibraryStrings.errorMessage),
                retry: { Task { await state.load() } }
            )
        case .loaded:
            loaded
        }
    }

    /// A read that succeeded: the catalogue, or one of the three ways it can have nothing to show.
    ///
    /// The three empties are separate states because they are separate facts and want separate
    /// answers: an empty catalogue has nothing to undo, an entirely archived one has the control
    /// that unhides it (`FR-1.1.5`), and a search that matched nothing has the filters that caused
    /// it and one tap out.
    @ViewBuilder private var loaded: some View {
        if state.isCatalogueEmpty {
            EmptyStateView(
                symbolName: "figure.strengthtraining.traditional",
                headline: Text(ExerciseLibraryStrings.emptyHeadline),
                message: Text(ExerciseLibraryStrings.emptyMessage),
                action: StateAction(Text(ExerciseLibraryStrings.createAction)) {
                    navigation?.navigate(to: .exerciseLibrary(.exerciseCreate))
                }
            )
        } else if state.isEverythingArchived {
            EmptyStateView(
                symbolName: "archivebox",
                headline: Text(ExerciseLibraryStrings.archivedOnlyHeadline),
                message: Text(ExerciseLibraryStrings.archivedOnlyMessage),
                // The same command the chip above carries, because it is the same control: a state
                // that named it without offering it would be a sentence pointing at a chip.
                action: StateAction(Text(ExerciseLibraryStrings.showArchivedFilter)) {
                    state.showsArchived = true
                }
            )
        } else if state.groups.isEmpty {
            EmptyStateView(
                symbolName: "magnifyingglass",
                headline: Text(ExerciseLibraryStrings.noMatchesHeadline),
                message: Text(ExerciseLibraryStrings.noMatchesMessage),
                action: StateAction(Text(ExerciseLibraryStrings.noMatchesAction)) {
                    state.clearFilters()
                }
            )
        } else {
            ExerciseGroupList(groups: state.groups)
        }
    }
}

/// The catalogue itself: one ``DesignSystem/GroupedSection`` per movement (`FR-1.1.1`).
///
/// Its own type, and taking groups rather than the state, because this is what the snapshot renders:
/// a reference over the screen would be a reference over the search field the system places and the
/// `.task` that reads a store.
struct ExerciseGroupList: View {
    /// The movements to show, already filtered and ordered.
    let groups: [ExerciseGroup]

    /// A lazy stack: 116 rows is the seeded catalogue and a custom one only grows it (`NFR-1.1`).
    var body: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.xl.points) {
            ForEach(groups) { group in
                GroupedSection(Text(ExerciseLibraryStrings.label(for: group.movement))) {
                    ForEach(group.exercises) { exercise in
                        NavigationLink(
                            value: Route.exerciseLibrary(.exerciseDetail(exerciseID: exercise.id))
                        ) {
                            ExerciseRow(exercise: exercise)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// One exercise, as a row (`FR-1.1.1`).
struct ExerciseRow: View {
    /// The exercise this row names.
    let exercise: Exercise

    /// Name, then what it is performed with, and a badge when the user wrote it or archived it.
    ///
    /// The whole row is one VoiceOver element (`G-4.2`): name, equipment and badge are one thing to
    /// say about one exercise, and three stops per row over 116 rows is the failure mode. The
    /// chevron is hidden — it says "this pushes", which the button trait already says.
    var body: some View {
        HStack(spacing: Spacing.md.points) {
            VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                Text(verbatim: exercise.name)
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.textPrimary)
                HStack(spacing: Spacing.sm.points) {
                    Text(ExerciseLibraryStrings.label(for: exercise.equipment))
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.textSecondary)
                    if exercise.isCustom {
                        Text(ExerciseLibraryStrings.customBadge)
                            .font(Typography.caption.font)
                            .foregroundStyle(ColorToken.brandAccent)
                    }
                    // Only ever visible when the list is showing archived rows, and then it is the
                    // only thing telling them from the rest (`FR-1.1.5`).
                    if exercise.isArchived {
                        Text(ExerciseLibraryStrings.archivedBadge)
                            .font(Typography.caption.font)
                            .foregroundStyle(ColorToken.textTertiary)
                    }
                }
            }
            Spacer(minLength: Spacing.sm.points)
            Image(systemName: "chevron.right")
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textTertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: TouchTarget.standard.points, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// `FR-1.1.2`'s four filters, as rows of chips.
///
/// **Chips rather than menus or pickers**, for `ImageRenderer`'s reason again: both of those are
/// UIKit-backed and would rasterise as placeholders, so the snapshot could not see which filter is
/// selected — which is the one thing about this bar worth a reference. They are screen-local rather
/// than a `DesignSystem` component: T-1.03 built the component set and a chip was not in it, and one
/// screen's control is not yet a shared one. The second screen that wants chips is the task that
/// should move them.
struct ExerciseFilterBar: View {
    /// The state whose filters these chips set.
    @Bindable var state: ExerciseListState

    /// One row per facet, each scrolling horizontally so a long vocabulary does not wrap into a wall.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md.points) {
            filterRow(
                title: ExerciseLibraryStrings.movementFilter,
                options: Movement.allCases,
                selection: $state.movementFilter,
                label: ExerciseLibraryStrings.label(for:)
            )
            filterRow(
                title: ExerciseLibraryStrings.equipmentFilter,
                options: Equipment.allCases,
                selection: $state.equipmentFilter,
                label: ExerciseLibraryStrings.label(for:)
            )
            filterRow(
                title: ExerciseLibraryStrings.originFilter,
                options: ExerciseOrigin.allCases,
                selection: $state.originFilter,
                label: ExerciseLibraryStrings.label(for:),
                trailing: { recencyChip }
            )
            archivedChip
        }
    }

    /// `FR-1.1.5`'s "show archived", on a line of its own and without a heading.
    ///
    /// **No heading, unlike the three rows above**, because it is not a facet with positions: it is
    /// one control that is either on or off, and its own label already says what it does. Giving it
    /// a heading would put it among `FR-1.1.2`'s filters, which is exactly what
    /// ``ExerciseListState/showsArchived`` is not.
    @ViewBuilder private var archivedChip: some View {
        FilterChip(
            label: Text(ExerciseLibraryStrings.showArchivedFilter),
            isSelected: state.showsArchived
        ) {
            state.showsArchived.toggle()
        }
    }

    /// One facet: its heading, then "All" and one chip per value.
    ///
    /// `trailing` is how the recency chip rides on the origin row instead of taking a row of its own
    /// for a single disabled control.
    @ViewBuilder private func filterRow<Value: Hashable, Trailing: View>(
        title: LocalizedStringResource,
        options: [Value],
        selection: Binding<Value?>,
        label: @escaping (Value) -> LocalizedStringResource,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm.points) {
            Text(title)
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            ScrollView(.horizontal) {
                HStack(spacing: Spacing.sm.points) {
                    FilterChip(
                        label: Text(ExerciseLibraryStrings.filterAll),
                        isSelected: selection.wrappedValue == nil
                    ) {
                        selection.wrappedValue = nil
                    }
                    ForEach(options, id: \.self) { option in
                        FilterChip(
                            label: Text(label(option)),
                            isSelected: selection.wrappedValue == option
                        ) {
                            // Tapping the selected chip clears it: with an "All" chip present that
                            // is a second way to the same place, and without it a filter row is a
                            // one-way door on a screen whose whole job is narrowing and widening.
                            selection.wrappedValue = selection.wrappedValue == option ? nil : option
                        }
                    }
                    trailing()
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    /// `FR-1.1.2`'s recency filter, shown and disabled until logging exists to be recent.
    ///
    /// The explanation sits beside it rather than in a tooltip, because a disabled control with no
    /// stated reason reads as a bug.
    @ViewBuilder private var recencyChip: some View {
        FilterChip(
            label: Text(ExerciseLibraryStrings.recentlyUsedFilter),
            isSelected: false,
            isEnabled: state.isRecencyFilterAvailable
        ) {}
        .accessibilityHint(Text(ExerciseLibraryStrings.recentlyUsedUnavailable))
    }
}

/// One filter value, as a tappable chip.
struct FilterChip: View {
    /// The chip's copy, built by the caller.
    let label: Text

    /// Whether this filter is the one in force.
    let isSelected: Bool

    /// Whether it can be tapped at all. `false` is a chip the user can see and not use.
    var isEnabled: Bool = true

    /// What tapping it does.
    let action: () -> Void

    /// A pill whose selection is carried by fill *and* by the selected accessibility trait — colour
    /// is never the only cue (`G-4.5`), and VoiceOver is told rather than shown.
    var body: some View {
        Button(action: action) {
            label
                .font(Typography.actionLabel.font)
                .foregroundStyle(isSelected ? ColorToken.onBrandAccent : ColorToken.textPrimary)
                .padding(.horizontal, Spacing.md.points)
                .padding(.vertical, Spacing.sm.points)
                .frame(minHeight: TouchTarget.standard.points)
                .background(
                    isSelected ? ColorToken.brandAccent : ColorToken.surfaceRaised,
                    in: .rect(cornerRadius: CornerRadius.control.points)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? Opacity.opaque.value : Opacity.disabled.value)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
