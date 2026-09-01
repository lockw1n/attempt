import DesignSystem
import DesignTokens
import Foundation
import SwiftUI

/// One target weight/rep/set group in the editor (`FR-15.2.1`'s amendment, `FR-15.2.2`).
///
/// **Three fields and no picker.** Every value here is a number the lifter types, and each crossing
/// back into one is `RoutineGroupDraft`'s — a `TextField` bound to an `Int` would revert what the
/// user is halfway through typing.
struct RoutineGroupRow: View {
    /// The draft this row writes into.
    @Bindable var store: RoutineEditorState

    /// What this row draws.
    let group: RoutineGroupDraft

    /// Where the group sits within its slot — the top set is `0`.
    let groupIndex: Int

    /// Where the slot sits in the routine.
    let slotIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.points) {
            header
            fields
            if group.isBlankWeight {
                // FR-15.2.2, said in a word rather than left as an empty box: a blank load and a
                // load of zero differ by nothing else on this row (`G-4.5`).
                Text(RoutinesStrings.editorBlankTarget)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.sm.points)
        .background(
            ColorToken.surface,
            in: .rect(cornerRadius: CornerRadius.control.points)
        )
    }

    /// The group's position and the three commands that act on it.
    @ViewBuilder private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm.points) {
                heading
                Spacer()
                commands
            }
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                heading
                HStack(spacing: Spacing.sm.points) { commands }
            }
        }
    }

    /// *Target 1*, *Target 2* — a position rather than a count, which is why it takes no plural.
    @ViewBuilder private var heading: some View {
        Text(RoutinesStrings.editorGroupHeading(groupIndex + 1))
            .font(Typography.metricLabel.font)
            .foregroundStyle(ColorToken.textSecondary)
    }

    /// Move up, move down, remove.
    @ViewBuilder private var commands: some View {
        SlotCommandButton(
            symbolName: "chevron.up",
            label: RoutinesStrings.editorGroupUp,
            isEnabled: groupIndex > 0
        ) {
            store.moveGroupUp(groupIndex, inSlotAt: slotIndex)
        }
        SlotCommandButton(
            symbolName: "chevron.down",
            label: RoutinesStrings.editorGroupDown,
            isEnabled: groupIndex < groupCount - 1
        ) {
            store.moveGroupDown(groupIndex, inSlotAt: slotIndex)
        }
        SlotCommandButton(
            symbolName: "minus.circle",
            label: RoutinesStrings.editorRemoveGroup,
            isEnabled: true
        ) {
            store.removeGroup(at: groupIndex, fromSlotAt: slotIndex)
        }
    }

    /// How many groups the slot holds, which is what the move-down command reads to know it is at
    /// the end. Zero where the slot has gone, which disables it.
    private var groupCount: Int {
        store.slots.indices.contains(slotIndex) ? store.slots[slotIndex].groups.count : 0
    }

    /// The weight, reps and sets, stacked where they stop sharing a line.
    @ViewBuilder private var fields: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Spacing.sm.points) { boxes }
            VStack(alignment: .leading, spacing: Spacing.sm.points) { boxes }
        }
    }

    /// The three boxes themselves, so the two layouts above cannot drift apart.
    @ViewBuilder private var boxes: some View {
        NumberFieldBox(
            label: RoutinesStrings.editorWeightLabel,
            prompt: RoutinesStrings.editorWeightPrompt,
            suffix: RoutinesStrings.unitSymbol(for: store.unit),
            text: binding(\.weightText)
        )
        NumberFieldBox(
            label: RoutinesStrings.editorRepsLabel,
            prompt: RoutinesStrings.editorRepsLabel,
            suffix: nil,
            text: binding(\.repsText)
        )
        NumberFieldBox(
            label: RoutinesStrings.editorSetsLabel,
            prompt: RoutinesStrings.editorSetsLabel,
            suffix: nil,
            text: binding(\.setsText)
        )
    }

    /// A binding onto one of the draft's fields that goes through the store's own mutator, so a
    /// keystroke retires a stale write diagnostic the way a name change does.
    private func binding(_ field: WritableKeyPath<RoutineGroupDraft, String>) -> Binding<String> {
        Binding(
            get: { group[keyPath: field] },
            set: { newValue in
                store.updateGroup(at: groupIndex, inSlotAt: slotIndex) { draft in
                    draft[keyPath: field] = newValue
                }
            }
        )
    }
}

/// A labelled numeric box with an optional unit after it.
///
/// The shape all three of a group's fields take; extracted for `LabelledTextField`'s reason — a
/// second copy is a second place to forget a Dynamic Type change.
struct NumberFieldBox: View {
    /// The label above the box, and the field's accessibility label.
    let label: LocalizedStringResource

    /// The placeholder inside an empty box.
    let prompt: LocalizedStringResource

    /// The unit drawn after the box, where the value has one.
    let suffix: LocalizedStringResource?

    /// What the user is typing.
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.points) {
            Text(label)
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            HStack(spacing: Spacing.xs.points) {
                TextField(text: $text, prompt: Text(prompt)) {
                    Text(label)
                }
                .labelsHidden()
                .font(Typography.numericValue.font)
                .foregroundStyle(ColorToken.textPrimary)
                .textFieldStyle(.plain)
                // G-3.4: the locale's own decimal separator, and no `.` key where the locale
                // writes a comma. `DesignSystem` owns the one place that is decided.
                .decimalKeyboard()
                if let suffix {
                    Text(suffix)
                        .font(Typography.metricLabel.font)
                        .foregroundStyle(ColorToken.textSecondary)
                }
            }
            .padding(Spacing.md.points)
            .background(
                ColorToken.surfaceRaised,
                in: .rect(cornerRadius: CornerRadius.control.points)
            )
        }
    }
}
