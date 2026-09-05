import DesignSystem
import Foundation
import PowerliftingCore
import SwiftUI

/// `FR-1.1.2`'s four filters, folded behind one row (`FR-16.5.4`).
///
/// **Folded, and that is the requirement rather than a tidy-up.** Three headed rows of chips plus
/// the archived control spent about 300 pt above the catalogue — a screen whose job is finding an
/// exercise, opening on everything except exercises. Folded, the row is one control and a chip per
/// narrowing actually in force, which is the only part of a filter bar a reader needs when they are
/// not changing it.
///
/// **Chips rather than menus or pickers**, for `ImageRenderer`'s reason: both of those are
/// UIKit-backed and would rasterise as placeholders, so the snapshot could not see which filter is
/// selected — which is the one thing about this bar worth a reference. They are screen-local rather
/// than a `DesignSystem` component: T-1.03 built the component set and a chip was not in it, and one
/// screen's control is not yet a shared one. The second screen that wants chips is the task that
/// should move them.
struct ExerciseFilterBar: View {
    /// The state whose filters these chips set.
    @Bindable var state: ExerciseListState

    /// Whether `FR-1.1.5`'s "show archived" is offered at all.
    ///
    /// `false` in the chooser, and that is the requirement rather than a simplification: archiving
    /// is what takes an exercise **out of the pickers**, so a picker that offered to put it back
    /// would be the one surface `FR-1.1.5` names. The browsing list keeps the control, which is
    /// where an archived exercise stays reachable from.
    var offersArchived = true

    /// The one row, and the facets themselves once it is opened.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md.points) {
            summary
            if state.areFiltersExpanded { facets }
        }
    }

    /// The folded row: the control that opens the facets, and what is narrowing the list right now.
    ///
    /// **The active chips are tappable and clear their own facet**, so a reader who can see a
    /// narrowing can undo it without opening anything — which is what makes folding the rest safe.
    /// Each carries a hint saying so: a chip labelled with the filter it names announces the
    /// subject and not the act (`G-4.2`).
    /// They scroll horizontally rather than wrapping, on the facet rows' own rule: four narrowings
    /// at the largest Dynamic Type size would otherwise be four lines above the catalogue.
    private var summary: some View {
        ScrollView(.horizontal) {
            ExerciseFilterSummary(
                activeFacets: state.activeFacets,
                isExpanded: state.areFiltersExpanded,
                toggleFilters: { state.areFiltersExpanded.toggle() },
                clear: { state.clear($0) })
        }
        .scrollIndicators(.hidden)
    }

    /// One row per facet, each scrolling horizontally so a long vocabulary does not wrap into a wall.
    @ViewBuilder private var facets: some View {
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
        if offersArchived {
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

    /// `FR-1.1.2`'s recency filter — live once something has been trained inside the window.
    ///
    /// **Still shown while it is unavailable, and the reason sits beside it**, because a disabled
    /// control with no stated cause reads as a bug. The two hints are opposite facts: one says what
    /// would turn the chip on, the other says what it narrows to.
    ///
    /// Tapping the chip while it is in force clears it, which is the same rule the other three rows
    /// use — the chip has no "All" beside it to go back to.
    @ViewBuilder private var recencyChip: some View {
        FilterChip(
            label: Text(ExerciseLibraryStrings.recentlyUsedFilter),
            isSelected: state.showsRecentOnly,
            isEnabled: state.isRecencyFilterAvailable
        ) {
            state.showsRecentOnly.toggle()
        }
        .accessibilityHint(
            Text(
                state.isRecencyFilterAvailable
                    ? ExerciseLibraryStrings.recentlyUsedAvailable(
                        days: ExerciseListState.recencyWindowInDays)
                    : ExerciseLibraryStrings.recentlyUsedUnavailable
            )
        )
    }
}

/// The folded row's own content — the control that opens the facets, and what is in force.
///
/// **Its own type because a `ScrollView`'s content is the only part of it a reference can see**
/// (`TR-1.12`). `ImageRenderer` draws the unsupported-view placeholder for a scroller and everything
/// inside it, so a reference over ``ExerciseFilterBar`` pictures the row as empty grey — which is
/// what the first recording of it did. The scroller stays a one-line wrapper up there; this is what
/// records.
struct ExerciseFilterSummary: View {
    /// Every narrowing in force, in the filter rows' own order.
    let activeFacets: [ExerciseListFacet]

    /// Whether the facets below are open — the "Filters" chip carries it as its selection.
    let isExpanded: Bool

    /// Opens and closes them.
    let toggleFilters: () -> Void

    /// Turns one narrowing off.
    let clear: (ExerciseListFacet) -> Void

    /// The row.
    var body: some View {
        HStack(spacing: Spacing.sm.points) {
            FilterChip(
                label: Text(ExerciseLibraryStrings.filtersLabel),
                isSelected: isExpanded,
                action: toggleFilters
            )
            .accessibilityHint(Text(ExerciseLibraryStrings.filtersHint))
            ForEach(activeFacets, id: \.self) { facet in
                FilterChip(
                    label: Text(ExerciseLibraryStrings.label(for: facet)),
                    isSelected: true
                ) {
                    clear(facet)
                }
                .accessibilityHint(Text(ExerciseLibraryStrings.clearHint(for: facet)))
            }
        }
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
