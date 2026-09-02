import DesignSystem
import DesignTokens
import Foundation
import SwiftUI

/// One exercise slot in the editor: its name, where it sits, and its target groups.
struct RoutineSlotCard: View {
    /// The draft this card writes into.
    @Bindable var store: RoutineEditorState

    /// What this card draws.
    let slot: RoutineSlotDraft

    /// Where the slot sits in the routine, which is what the reorder commands move.
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md.points) {
            header
            ForEach(Array(slot.groups.enumerated()), id: \.element.id) { groupIndex, group in
                RoutineGroupRow(
                    store: store, group: group, groupIndex: groupIndex, slotIndex: index)
            }
            Button {
                store.addGroup(toSlotAt: index)
            } label: {
                Text(RoutinesStrings.editorAddGroup)
            }
            .buttonStyle(.primaryAction(.intrinsic))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md.points)
        .background(
            ColorToken.surfaceRaised,
            in: .rect(cornerRadius: CornerRadius.control.points)
        )
    }

    /// The exercise's name and the three commands that act on the slot as a whole.
    ///
    /// **Explicit move buttons rather than a drag**, which is the active session's own call and for
    /// its two reasons: `TR-1.12`'s `ImageRenderer` harness rasterises `List`'s `.onMove` as a
    /// placeholder, and a drag is the one reorder gesture VoiceOver and Switch Control cannot
    /// perform (`G-4.2`).
    @ViewBuilder private var header: some View {
        // A stack rather than a line, because three 44pt controls and a name do not share one at
        // the largest Dynamic Type size — the set row measured the same thing with two.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm.points) {
                name
                Spacer()
                commands
            }
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                name
                HStack(spacing: Spacing.sm.points) { commands }
            }
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
                Text(RoutinesStrings.editorUnnamedExercise)
            } else {
                Text(verbatim: slot.name)
            }
        }
        .font(Typography.cardTitle.font)
        .foregroundStyle(ColorToken.textPrimary)
    }

    /// Move up, move down, remove — each a 44pt target (`G-4.3`) with a label rather than a bare
    /// glyph (`G-4.2`).
    @ViewBuilder private var commands: some View {
        SlotCommandButton(
            symbolName: "chevron.up",
            label: RoutinesStrings.editorMoveUp,
            isEnabled: index > 0
        ) {
            store.moveSlotUp(index)
        }
        SlotCommandButton(
            symbolName: "chevron.down",
            label: RoutinesStrings.editorMoveDown,
            isEnabled: index < store.slots.count - 1
        ) {
            store.moveSlotDown(index)
        }
        SlotCommandButton(
            symbolName: "minus.circle",
            label: RoutinesStrings.editorRemoveExercise,
            isEnabled: true
        ) {
            store.removeSlot(at: index)
        }
    }
}

/// One of a slot's or a group's icon commands, sized and labelled the same way each time.
struct SlotCommandButton: View {
    /// The glyph drawn in it.
    let symbolName: String

    /// What it does, as VoiceOver's label — the glyph carries no name of its own (`G-4.2`).
    let label: LocalizedStringResource

    /// Whether the command can act. A disabled button is drawn rather than hidden, so the row's
    /// controls do not move as the list is reordered.
    let isEnabled: Bool

    /// What it does.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(Typography.body.font)
                .frame(
                    minWidth: TouchTarget.standard.points,
                    minHeight: TouchTarget.standard.points)
        }
        .buttonStyle(.plain)
        .foregroundStyle(ColorToken.brandAccent)
        .disabled(!isEnabled)
        .opacity(isEnabled ? Opacity.opaque.value : Opacity.disabled.value)
        .accessibilityLabel(Text(label))
    }
}
