import DesignSystem
import DesignTokens
import Foundation
import SwiftUI

/// One target weight/rep/set group, in the app's set notation (`FR-17.10.1`, `FR-15.2.2`).
///
/// **`[105] kg × [4] × [4]`, and the notation is the label.** Where the three boxes share a line
/// the multiplication signs say what each one is, which is how the plan reads everywhere else in
/// the app (`WeekPlanTarget`'s own rendering); where they do not fit — at the larger Dynamic Type
/// sizes — they stack and each carries its written label instead. Both layouts draw the same three
/// boxes, and VoiceOver reads the label either way.
///
/// **Three fields and no picker.** Every value here is a number the lifter types, and each crossing
/// back into one is `RoutineGroupDraft`'s — a `TextField` bound to an `Int` would revert what the
/// user is halfway through typing.
struct RoutineGroupRow: View {
    /// The store this row writes into.
    @Bindable var store: WeekEditorState

    /// What this row draws.
    let group: RoutineGroupDraft

    /// Where the group sits within its exercise — the top set is `0`.
    let groupIndex: Int

    /// Where the exercise sits in the day.
    let slotIndex: Int

    /// Where the day sits in the week.
    let dayIndex: Int

    /// How large the user reads at — what decides whether this row is the notation or a stack
    /// (`NFR-1.10`).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.points) {
            header
            fields
            if group.isBlankWeight {
                // FR-15.2.2, said in a word rather than left as an empty box: a blank load and a
                // load of zero differ by nothing else on this row (`G-4.5`).
                Text(RoutinesStrings.targetBlank)
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

    /// The group's position and the menu that acts on it.
    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.sm.points) {
            Text(RoutinesStrings.targetGroupHeading(groupIndex + 1))
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            Spacer(minLength: Spacing.sm.points)
            menu
        }
    }

    /// Move up, move down, remove — behind one labelled menu (`FR-17.10.1`, `G-4.2`).
    private var menu: some View {
        SlotCommandMenu(label: RoutinesStrings.targetMenu) {
            Button {
                Task {
                    await store.moveTarget(
                        groupIndex, by: -1, inSlot: slotIndex, inDayAt: dayIndex)
                }
            } label: {
                Text(RoutinesStrings.targetMoveUp)
            }
            .disabled(groupIndex == 0)
            Button {
                Task {
                    await store.moveTarget(groupIndex, by: 1, inSlot: slotIndex, inDayAt: dayIndex)
                }
            } label: {
                Text(RoutinesStrings.targetMoveDown)
            }
            .disabled(groupIndex >= groupCount - 1)
            Button(role: .destructive) {
                Task {
                    await store.removeTarget(groupIndex, inSlot: slotIndex, inDayAt: dayIndex)
                }
            } label: {
                Text(RoutinesStrings.targetRemove)
            }
        }
    }

    /// How many groups the exercise holds, which is what the move-down command reads to know it is
    /// at the end. Zero where the exercise has gone, which disables it.
    private var groupCount: Int {
        store.slot(slotIndex, inDayAt: dayIndex)?.groups.count ?? 0
    }

    /// The notation below the accessibility sizes, the labelled stack at them.
    ///
    /// **Read from the type size rather than measured with `ViewThatFits`, and that is a
    /// correction rather than a preference.** The first version measured, and the stack won at every
    /// size: a `TextField`'s ideal width is its prompt's, so three boxes plus two signs never fit a
    /// row and the notation `FR-17.10.1` asks for was never drawn once. The same trap is why the
    /// inline boxes take their own labels as prompts — "Decide in session" is the load's placeholder
    /// where there is a column to write it in, and a whole row's width where there is not.
    @ViewBuilder private var fields: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                weightBox(inline: false)
                repsBox(inline: false)
                setsBox(inline: false)
            }
        } else {
            HStack(alignment: .center, spacing: Spacing.sm.points) {
                // NO `layoutPriority` HERE, and it was tried: a `TextField`'s ideal width is
                // unbounded, so giving the load the higher priority let it claim the whole row and
                // pushed the reps and sets off the screen. The three boxes divide the row evenly
                // and the load's placeholder truncates when the field is empty, which the caption
                // under a blank row already says in full.
                weightBox(inline: true)
                times
                repsBox(inline: true)
                times
                setsBox(inline: true)
            }
        }
    }

    /// The multiplication sign between two boxes — copy, so a language that does not write the
    /// notation this way has somewhere to say so.
    private var times: some View {
        Text(RoutinesStrings.targetSeparator)
            .font(Typography.numericValue.font)
            .foregroundStyle(ColorToken.textSecondary)
            // The three fields already name themselves to VoiceOver; a sign between them would be
            // read as a word (`G-4.2`).
            .accessibilityHidden(true)
    }

    /// The load (`FR-15.2.2`: blank is a prescription).
    ///
    /// - Parameter inline: Whether this is the notation rather than the labelled stack.
    /// - Returns: The box.
    private func weightBox(inline: Bool) -> some View {
        NumberFieldBox(
            label: RoutinesStrings.targetWeightLabel,
            // `FR-15.2.2`'s "decide it in the session" only where there is room to write it; the
            // caption under a blank row says the same thing either way.
            prompt: inline
                ? RoutinesStrings.targetWeightLabel : RoutinesStrings.targetWeightPrompt,
            suffix: RoutinesStrings.unitSymbol(for: store.unit),
            showsLabel: !inline,
            text: binding(\.weightText)
        )
    }

    /// The repetitions prescribed per set.
    ///
    /// - Parameter inline: Whether this is the notation rather than the labelled stack.
    /// - Returns: The box.
    private func repsBox(inline: Bool) -> some View {
        NumberFieldBox(
            label: RoutinesStrings.targetRepsLabel,
            prompt: RoutinesStrings.targetRepsLabel,
            suffix: nil,
            showsLabel: !inline,
            text: binding(\.repsText)
        )
    }

    /// The sets prescribed.
    ///
    /// - Parameter inline: Whether this is the notation rather than the labelled stack.
    /// - Returns: The box.
    private func setsBox(inline: Bool) -> some View {
        NumberFieldBox(
            label: RoutinesStrings.targetSetsLabel,
            prompt: RoutinesStrings.targetSetsLabel,
            suffix: nil,
            showsLabel: !inline,
            text: binding(\.setsText)
        )
    }

    /// A binding onto one of the draft's fields.
    ///
    /// **The keystroke lands synchronously and the write is spawned after it**, which is the whole
    /// of ``WeekEditorState``'s write-through rule at the one place it is exercised: a mutation
    /// deferred into the `Task` would let the field render the previous value for a turn, and a
    /// write performed inline is not something a `Binding`'s setter can do. Two keystrokes' writes
    /// are safe in either order because each reads the draft as it stands when it runs — see
    /// ``WeekEditorState/commitTarget(_:inSlot:inDayAt:)``.
    ///
    /// - Parameter field: Which of the three the box writes.
    /// - Returns: The binding.
    private func binding(_ field: WritableKeyPath<RoutineGroupDraft, String>) -> Binding<String> {
        Binding(
            get: { group[keyPath: field] },
            set: { newValue in
                let path = (group: groupIndex, slot: slotIndex, day: dayIndex)
                let changed = store.editTarget(path.group, inSlot: path.slot, inDayAt: path.day) {
                    $0[keyPath: field] = newValue
                }
                guard changed else { return }
                Task {
                    await store.commitTarget(path.group, inSlot: path.slot, inDayAt: path.day)
                }
            }
        )
    }
}

/// A numeric box with an optional written label above it and an optional unit after it.
///
/// The shape all three of a group's fields take; extracted for `LabelledTextField`'s reason — a
/// second copy is a second place to forget a Dynamic Type change.
///
/// **The label can be hidden and never removed.** Where the notation carries the meaning
/// (`RoutineGroupRow`) the written label is not drawn, but the field keeps it: `.labelsHidden()`
/// hides a label visually and leaves it to VoiceOver, so the box announces itself either way
/// (`G-4.2`).
struct NumberFieldBox: View {
    /// The label above the box, and the field's accessibility label.
    let label: LocalizedStringResource

    /// The placeholder inside an empty box.
    let prompt: LocalizedStringResource

    /// The unit drawn after the box, where the value has one.
    let suffix: LocalizedStringResource?

    /// Whether the written label is drawn above the box.
    let showsLabel: Bool

    /// What the user is typing.
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.points) {
            if showsLabel {
                Text(label)
                    .font(Typography.metricLabel.font)
                    .foregroundStyle(ColorToken.textSecondary)
            }
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
