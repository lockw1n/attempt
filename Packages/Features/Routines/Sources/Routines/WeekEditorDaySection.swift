import AppNavigation
import DesignSystem
import DesignTokens
import Foundation
import SwiftUI

/// One day of the week: its position, its name, and — while it is open — its exercises
/// (`FR-17.10.1`).
///
/// **Folded but for the one being edited**, which is what a six-day week needs. Three days of six
/// exercises at two targets each is thirty-six rows of three fields; open at once that is a screen
/// nobody can find their place on, and at `accessibility3` it is one `TR-1.12`'s `ImageRenderer`
/// cannot record at all — it hands back nothing past about seven thousand pixels of height, and a
/// blank reference is invisible to the harness.
///
/// **The header is the disclosure and the menu is beside it, not inside it.** Two controls over one
/// rectangle is a control the push wins every time (`WeekDayCardView`'s own note), so the fold takes
/// the row's width and the menu takes its own 44 pt (`G-4.3`).
struct WeekEditorDaySection: View {
    /// The store this section's commands run against.
    @Bindable var store: WeekEditorState

    /// What this section draws.
    let day: WeekEditorDay

    /// Where the day sits in the week, which is what the moves are relative to.
    let index: Int

    /// Opens the one-field prompt that retitles it. The prompt is the screen's — a store cannot
    /// ask.
    let rename: () -> Void

    /// Asks whether to take it out of the week. The confirmation is the screen's, for the same
    /// reason.
    let remove: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md.points) {
                header
                if isOpen {
                    exercises
                    addExercise
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Whether this day is the one unfolded.
    private var isOpen: Bool { store.openDayID == day.id }

    /// The position, the name, the chevron, and the day's own menu.
    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.sm.points) {
            Button {
                store.openDayID = isOpen ? nil : day.id
            } label: {
                HStack(spacing: Spacing.sm.points) {
                    VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                        Text(RoutinesStrings.dayNumber(index + 1))
                            .font(Typography.caption.font)
                            .foregroundStyle(ColorToken.textSecondary)
                        name
                    }
                    Spacer(minLength: Spacing.sm.points)
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.textTertiary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue(
                Text(isOpen ? RoutinesStrings.dayExpanded : RoutinesStrings.dayCollapsed))
            menu
        }
    }

    /// The day's name, the stand-in for one that holds none, or the sentence for a routine that has
    /// been archived.
    ///
    /// **A `Text` rather than a resource where it is the lifter's own words** (`RoutineRow`'s
    /// rule): a stored name is never looked up in this module's copy, while both stand-ins are this
    /// module's and always are.
    @ViewBuilder private var name: some View {
        Group {
            if let name = day.name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(verbatim: name)
                    .foregroundStyle(ColorToken.textPrimary)
            } else if day.name == nil {
                Text(RoutinesStrings.dayArchived)
                    .foregroundStyle(ColorToken.textTertiary)
            } else {
                Text(RoutinesStrings.dayUnnamed)
                    .foregroundStyle(ColorToken.textTertiary)
            }
        }
        .font(Typography.actionLabel.font)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// `FR-17.10.4`'s five day commands, behind one labelled menu (`G-4.2`).
    ///
    /// **A menu rather than five buttons**, which is what makes a day's header a header: the four
    /// icon buttons the program editor drew beside a day's name did not share a line at
    /// `accessibility3` and had to stack, so every day cost three rows before it said anything.
    private var menu: some View {
        SlotCommandMenu(label: RoutinesStrings.dayMenu) {
            Button(action: rename) { Text(RoutinesStrings.dayRename) }
            Button {
                Task { await store.duplicateDay(day.id) }
            } label: {
                Text(RoutinesStrings.dayDuplicate)
            }
            Button {
                Task { await store.moveDay(at: index, by: -1) }
            } label: {
                Text(RoutinesStrings.dayMoveUp)
            }
            .disabled(index == 0)
            Button {
                Task { await store.moveDay(at: index, by: 1) }
            } label: {
                Text(RoutinesStrings.dayMoveDown)
            }
            .disabled(index >= store.days.count - 1)
            Button(role: .destructive, action: remove) { Text(RoutinesStrings.dayRemove) }
        }
    }

    /// The day's exercises in order, or the sentence for a day that prescribes nothing.
    @ViewBuilder private var exercises: some View {
        if day.slots.isEmpty {
            EmptyStateView(
                symbolName: "figure.strengthtraining.traditional",
                headline: Text(RoutinesStrings.exercisesEmptyHeadline),
                message: Text(RoutinesStrings.exercisesEmptyMessage)
            )
        } else {
            ForEach(Array(day.slots.enumerated()), id: \.element.id) { slotIndex, slot in
                RoutineSlotCard(
                    store: store, slot: slot, slotIndex: slotIndex, dayIndex: index)
            }
        }
    }

    /// The way to the catalogue, as a push rather than a sheet (`FR-17.10.6`).
    ///
    /// It carries no day: which day is being added to is the one that is open, which is one fact
    /// about the app rather than a parameter of a push — see ``WeekEditorState/addExercise(id:)``.
    private var addExercise: some View {
        NavigationLink(value: Route.exerciseLibrary(.routineExercisePicker)) {
            Text(RoutinesStrings.exerciseAdd)
        }
        // Secondary: **Save** is this screen's one filled accent (`FR-16.6.4`), and this is drawn
        // once per open day.
        .buttonStyle(.secondaryAction(.fill))
    }
}
