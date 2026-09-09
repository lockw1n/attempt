import DesignSystem
import DesignTokens
import Foundation
import SwiftUI

/// One exercise of a day: its name, its targets, and the commands that act on it as a whole
/// (`FR-17.10.1`).
struct RoutineSlotCard: View {
    /// The store this card writes into.
    @Bindable var store: WeekEditorState

    /// What this card draws.
    let slot: RoutineSlotDraft

    /// Where the exercise sits in the day, which is what the reorder commands move.
    let slotIndex: Int

    /// Where the day sits in the week.
    let dayIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md.points) {
            header
            ForEach(Array(slot.groups.enumerated()), id: \.element.id) { groupIndex, group in
                RoutineGroupRow(
                    store: store,
                    group: group,
                    groupIndex: groupIndex,
                    slotIndex: slotIndex,
                    dayIndex: dayIndex)
            }
            Button {
                store.addTarget(toSlot: slotIndex, inDayAt: dayIndex)
            } label: {
                Text(RoutinesStrings.targetAdd)
            }
            // Secondary: this is drawn once per exercise, so a three-exercise day would otherwise
            // put three filled accents on a screen that already has **Save** (`FR-16.6.4`).
            // Intrinsic width is unchanged — `PrimaryActionWidth` chooses width and nothing else,
            // which is why this call site is invisible to a grep for `.fill`.
            .buttonStyle(.secondaryAction(.intrinsic))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md.points)
        .background(
            ColorToken.surfaceRaised,
            in: .rect(cornerRadius: CornerRadius.control.points)
        )
    }

    /// The exercise's name and its menu.
    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.sm.points) {
            name
            Spacer(minLength: Spacing.sm.points)
            menu
        }
    }

    /// The exercise's name, or the stand-in for a slot whose catalogue row could not be read.
    ///
    /// **A `Text` rather than a resource**, for `RoutineRow`'s reason: a stored exercise name is
    /// the catalogue's words and is never looked up in this module's copy, while the stand-in is
    /// this module's and always is.
    @ViewBuilder private var name: some View {
        Group {
            if slot.name.isEmpty {
                Text(RoutinesStrings.exerciseUnnamed)
            } else {
                Text(verbatim: slot.name)
            }
        }
        .font(Typography.cardTitle.font)
        .foregroundStyle(ColorToken.textPrimary)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Move up, move down, remove — behind one labelled menu (`FR-17.10.1`, `G-4.2`).
    private var menu: some View {
        SlotCommandMenu(label: RoutinesStrings.exerciseMenu) {
            Button {
                Task { await store.moveSlot(slotIndex, by: -1, inDayAt: dayIndex) }
            } label: {
                Text(RoutinesStrings.exerciseMoveUp)
            }
            .disabled(slotIndex == 0)
            Button {
                Task { await store.moveSlot(slotIndex, by: 1, inDayAt: dayIndex) }
            } label: {
                Text(RoutinesStrings.exerciseMoveDown)
            }
            .disabled(slotIndex >= slotCount - 1)
            Button(role: .destructive) {
                Task { await store.removeSlot(slotIndex, inDayAt: dayIndex) }
            } label: {
                Text(RoutinesStrings.exerciseRemove)
            }
        }
    }

    /// How many exercises the day holds, which is what the move-down command reads to know it is at
    /// the end. Zero where the day has gone, which disables it.
    private var slotCount: Int {
        store.days.indices.contains(dayIndex) ? store.days[dayIndex].slots.count : 0
    }
}

/// The overflow shape every command menu on this screen takes (`FR-17.10.1`, `G-4.2`, `G-4.3`).
///
/// **One type rather than the glyph written at each site**, for `NumberFieldBox`'s reason: a second
/// copy is a second place to forget the 44 pt frame or the label. A `Menu`'s *button* is what a
/// reference can see; the presented menu is UIKit's and renders as `ImageRenderer`'s placeholder,
/// so the items are proven by a test rather than by a picture.
struct SlotCommandMenu<Content: View>: View {
    /// What the menu is, as VoiceOver's label — named for the menu rather than for any item in it.
    let label: LocalizedStringResource

    /// The items.
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textSecondary)
                .frame(width: TouchTarget.standard.points, height: TouchTarget.standard.points)
                .contentShape(.rect)
        }
        .accessibilityLabel(Text(label))
    }
}
