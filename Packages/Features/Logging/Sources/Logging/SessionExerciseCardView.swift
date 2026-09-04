import DesignSystem
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

// A file of its own rather than the foot of `SessionExercisesView.swift`, which had reached
// SwiftLint's file ceiling: the list and the card grow for different reasons — a state being added
// to the screen, and content being added inside one exercise.

/// One exercise in the workout (`FR-1.2.13`).
///
/// **The card shape the rest of Track C fills in.** T-1.22 through T-1.27 add content *inside* this
/// card — sets, modifiers, the previous session's performance — rather than new card shapes.
struct SessionExerciseCard: View {
    /// The exercise, its entry and its sets.
    let item: SessionExercise

    /// Where it sits in the workout, zero-based — what the move controls move it from.
    let position: Int

    /// How many exercises the workout has, so the ends of the list can refuse to move further.
    let count: Int

    /// Whether the card is open.
    let isExpanded: Bool

    /// Opens or closes it.
    let toggle: () -> Void

    /// Whether this card's warmup group is open (`FR-1.2.14`).
    let areWarmupsExpanded: Bool

    /// Opens or closes it, independently of the card's own fold.
    let toggleWarmups: () -> Void

    /// Which of this card's set groups the user has opened (`FR-16.1.3`), keyed on the group — which
    /// is its first set's id.
    ///
    /// **Held above the card rather than inside it**, on ``areWarmupsExpanded``'s rule: a card is
    /// rebuilt on every set written into the workout, and a fold kept in the view's own `@State`
    /// would close every group each time one did.
    let expandedGroups: Set<UUID>

    /// Opens or closes one of them.
    let toggleGroup: (UUID) -> Void

    /// Moves the named exercise by that many places (`FR-1.2.2`).
    let move: (UUID, Int) -> Void

    /// The unit this card's loads are shown in (`G-3.1`).
    let unit: MassUnit

    /// What this exercise looked like the last time it was trained (`FR-1.2.10`).
    let previous: PreviousPerformanceState

    /// Which sets hold a record (`FR-1.6.3`), keyed on the set.
    ///
    /// **The workout's map rather than this card's slice**, because slicing it would need the card to
    /// know which of the exercise's records were set today — and a record's source set is not
    /// necessarily on this card at all. The lookup is by set, so a map holding other cards' sets
    /// answers this one exactly as well.
    let personalRecords: SessionRecordMarks

    /// Opens the set editor over this exercise (`FR-1.2.3`, `FR-1.2.6`).
    let logSet: (SetEditorTarget) -> Void

    /// Marks one of this card's sets as a warmup or as working (`FR-1.2.4`).
    let mark: (SetEntry, Bool) -> Void

    /// Marks one of this card's sets as completed or failed (`FR-1.2.5`).
    let markCompleted: (SetEntry, Bool) -> Void

    /// Opens `FR-1.2.7`'s editor over one of them.
    let edit: (SetEntry) -> Void

    /// Checks this exercise off, or takes the check back (`FR-15.3.4`).
    let markDone: (UUID, Bool) -> Void

    /// Logs the next planned set exactly as prescribed (`NFR-15.3`).
    let logPlanned: (UUID) -> Void

    /// Appends a set equal to the one named, against this exercise (`FR-16.1.4`) — the entry, then
    /// the set to copy.
    ///
    /// **The set rather than the group**, because a group is recomputed on every read and holds no
    /// identity past its first member's: what the write needs to name is the `SetEntry` it copies.
    let logNext: (UUID, SetEntry) -> Void

    /// Which locale the numbers on this card are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The header, and the body where the card is open.
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md.points) {
                header
                if isExpanded {
                    contents
                }
            }
        }
    }

    /// The exercise's name, whether it is finished, and the control that folds the card.
    ///
    /// **The whole header is the disclosure control**, so the tap target is the card's width rather
    /// than a chevron (`NFR-1.10`), and it carries the expanded trait so VoiceOver announces the
    /// state rather than only the glyph (`G-4.2`).
    private var header: some View {
        HStack(spacing: Spacing.sm.points) {
            Button(action: toggle) {
                HStack(spacing: Spacing.sm.points) {
                    VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                        name
                            .font(Typography.cardTitle.font)
                            .foregroundStyle(ColorToken.textPrimary)
                        if let caption {
                            caption
                                .font(Typography.caption.font)
                                // A skip is not a good outcome, only a recorded one, and `G-7.3`
                                // reserves the semantic palette for what it distinguishes.
                                .foregroundStyle(
                                    item.isSkipped ? ColorToken.textSecondary : ColorToken.positive)
                        }
                    }
                    Spacer(minLength: Spacing.sm.points)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.textTertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: TouchTarget.standard.points)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            // A **value**, not a trait. SwiftUI has no "expanded" trait, and `.isSelected` — which
            // already means a chosen filter chip everywhere else in this app — announces "Selected"
            // for a card that is merely open, which is a different fact. The chevron beside it is
            // hidden, so this is the only thing carrying the fold to VoiceOver (`G-4.2`).
            .accessibilityValue(
                Text(
                    isExpanded
                        ? LoggingStrings.sessionExerciseExpanded
                        : LoggingStrings.sessionExerciseCollapsed
                )
            )
            moveControls
        }
    }

    /// `FR-1.2.2`'s reorder, as two buttons rather than a drag.
    ///
    /// **Explicit controls, and that is a decision twice over.** A drag lives on `List`'s `.onMove`,
    /// which is UIKit-backed and would take this screen out of `TR-1.12`'s gate; and a drag is the
    /// one reorder gesture VoiceOver and Switch Control users cannot perform, where a pair of
    /// buttons is reachable by every input (`G-4.2`, `NFR-1.10`). Each is disabled at the end of the
    /// list it cannot move past, rather than hidden — a control that disappears at the edges is a
    /// control the user has to rediscover.
    ///
    /// **Arrows, not chevrons**, though the fold control beside them is one: three chevrons in a row
    /// is one glyph saying three things, and the two here are the pair a user has to tell apart at a
    /// glance mid-workout.
    private var moveControls: some View {
        HStack(spacing: Spacing.xxs.points) {
            moveButton(
                symbolName: "arrow.up",
                label: LoggingStrings.sessionExerciseMoveUp,
                isEnabled: position > 0
            ) {
                move(item.id, -1)
            }
            moveButton(
                symbolName: "arrow.down",
                label: LoggingStrings.sessionExerciseMoveDown,
                isEnabled: position < count - 1
            ) {
                move(item.id, 1)
            }
        }
    }

    /// One of the two move controls.
    private func moveButton(
        symbolName: String,
        label: LocalizedStringResource,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textSecondary)
                // Both dimensions at the minimum, not one: a control half a target tall is one
                // `NFR-1.10` cannot be argued out of, and the two buttons sit side by side rather
                // than stacked precisely so neither has to be shortened to fit the header.
                .frame(width: TouchTarget.standard.points, height: TouchTarget.standard.points)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? Opacity.opaque.value : Opacity.disabled.value)
        .accessibilityLabel(Text(label))
    }

    /// What the card holds while it is open: `FR-1.2.10`'s previous session, the sets logged against
    /// it, and the two ways to add one.
    ///
    /// **An empty card says so in a sentence rather than in one of `FR-1.13.1`'s states.** Zero sets
    /// is a count the same way three is, and a state placeholder per card would be five of them down
    /// a workout.
    private var contents: some View {
        // Bound once here rather than read inside the loop: `plannedTargets` walks the working sets
        // to place each one, so a computed property touched per row is that walk restarted on every
        // line.
        let targets = item.plannedTargets
        return VStack(alignment: .leading, spacing: Spacing.sm.points) {
            PreviousPerformanceStrip(state: previous, unit: unit)
            if item.sets.isEmpty {
                Text(LoggingStrings.setListEmpty)
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.textSecondary)
            } else {
                warmupGroup
                // Only the last of them carries `FR-16.1.4`'s append — see ``SetGroupRow/logNext``
                // for why "next" is a claim about the last group rather than about any of them.
                ForEach(workingGroups) { group in
                    groupRow(
                        for: group,
                        targets: targets,
                        logNext: group.id == workingGroups.last?.id
                            ? { logNext(item.id, group.last.record) } : nil
                    )
                }
            }
            plannedNext
            setCommands
            ExerciseDoneToggle(isMarkedDone: item.entry.isMarkedDone) {
                markDone(item.id, !item.entry.isMarkedDone)
            }
        }
    }

    /// How the card describes itself under its own name, or nothing.
    ///
    /// **Three states rather than two, and the lifter's verdict outranks the sets'.** `FR-1.2.13`'s
    /// "Completed" is the sets speaking; `FR-15.3.4`'s check-off is the lifter, and where they
    /// disagree it is the lifter who decided. A card checked off with none of the work behind it
    /// says so in a different word — a skip is an outcome the plan has to be able to record.
    private var caption: Text? {
        if item.isSkipped { return Text(LoggingStrings.sessionExerciseSkipped) }
        if item.entry.isMarkedDone { return Text(LoggingStrings.sessionExerciseMarkedDone) }
        if item.isComplete { return Text(LoggingStrings.sessionExerciseCompleted) }
        return nil
    }

    /// What the routine prescribes next, where one does and the plan is not yet exhausted
    /// (`FR-15.3.1`, `NFR-15.3`).
    ///
    /// **Above the two set commands rather than below them.** On a card that carries a plan this is
    /// the dominant logging action — it writes what the routine prescribed, where **Repeat set**
    /// copies whatever was done last — and it is the tap `NFR-15.3` counts, so it sits nearest the
    /// sets it follows. On a card nobody planned it is not drawn at all, which leaves `FR-1.2.6`'s
    /// duplicate exactly where Phase 1 put it.
    @ViewBuilder private var plannedNext: some View {
        if let group = item.nextPlannedGroup {
            PlannedNextSetSection(target: group, unit: unit) { logPlanned(item.id) }
        }
    }

    /// `FR-1.2.14`'s warmups: a heading that folds them, and the rows beneath it while it is open.
    ///
    /// **Drawn as a leading group rather than in place**, and that is the requirement rather than a
    /// rearrangement for looks: a group is only collapsible if it is contiguous, and marking a set
    /// as a warmup after the fact — which `FR-1.2.4` allows and this card offers — otherwise leaves
    /// one warmup stranded between two working sets with nothing able to fold it. Grouping costs the
    /// numbering nothing, because a number counts the sets of its own kind before it and
    /// partitioning does not change that for either kind. See ``SetNumbering``.
    ///
    /// **The heading is drawn only when there are warmups.** A fold control over nothing is a
    /// control that promises rows the card does not have.
    @ViewBuilder private var warmupGroup: some View {
        if !warmups.isEmpty {
            WarmupSectionHeader(
                count: warmups.count, isExpanded: areWarmupsExpanded, toggle: toggleWarmups)
            if areWarmupsExpanded {
                // No targets, and by construction rather than by lookup: a warmup consumes no
                // planned set, so ``SessionExercise/plannedTargets`` never holds one.
                ForEach(warmupGroups) { groupRow(for: $0, targets: [:], logNext: nil) }
            }
        }
    }

    /// One group's line, wherever on the card it is drawn (`FR-16.1.1`).
    ///
    /// A group of one draws as the row it always was — see ``SetGroupRow``.
    ///
    /// - Parameters:
    ///   - group: The run of identical sets, and their numbers.
    ///   - targets: What a routine planned for each set, keyed on the set (`FR-15.3.1`).
    ///   - logNext: `FR-16.1.4`'s append, on the one group that gets it, or `nil`.
    /// - Returns: The line.
    private func groupRow(
        for group: NumberedSetGroup,
        targets: [UUID: PlannedTargetGroup],
        logNext: (() -> Void)?
    ) -> some View {
        SetGroupRow(
            group: group,
            unit: unit,
            isExpanded: expandedGroups.contains(group.id),
            toggle: { toggleGroup(group.id) },
            mark: mark,
            markCompleted: markCompleted,
            edit: edit,
            recordSchemes: { personalRecords.schemes(forSetID: $0) },
            target: { targets[$0] },
            logNext: logNext
        )
    }

    /// This card's sets, each carrying its number within its own sequence (`FR-1.2.14`).
    private var numberedSets: [NumberedSet] { SetNumbering.numbered(item.sets) }

    /// The warmups among them, in the order they were logged.
    private var warmups: [NumberedSet] { numberedSets.filter(\.isWarmup) }

    /// The work proper, likewise.
    private var workingSets: [NumberedSet] { numberedSets.filter { !$0.isWarmup } }

    /// The work proper as `FR-16.1.1`'s groups.
    ///
    /// **Grouped after the partition, not before it.** The card draws the warmups above the work, so
    /// a warmup logged between two identical working sets is not between them on screen — and two
    /// groups of two where the reader sees four adjacent identical rows would be a split with
    /// nothing visible behind it. ``SetNumbering`` makes the same argument about the numbering.
    private var workingGroups: [NumberedSetGroup] { SetNumbering.grouped(workingSets) }

    /// The warmups likewise, inside their own fold.
    private var warmupGroups: [NumberedSetGroup] { SetNumbering.grouped(warmups) }

    /// `FR-1.2.6`'s duplicate, then `FR-1.2.3`'s blank form.
    ///
    /// **Both secondary, and both the same weight** (`FR-16.6.4`, `G-7.2`). **Repeat set** was the
    /// filled one, on the argument that it is the dominant logging action — which stopped being true
    /// the moment `FR-16.1.4`'s **Log next set** went on the group above it, and was never
    /// affordable at six cards: one accent used once per exercise is a screen with six primary
    /// actions and no primary action. The one filled button on this screen is **Finish workout**.
    ///
    /// **Side by side, wrapping at `NFR-1.10`'s ceiling.** They were stacked because two commands
    /// sharing a row at `accessibility3` are two commands with three characters each — which is the
    /// same finding, answered by `ViewThatFits` rather than by giving up the row at every size.
    ///
    /// **Both carry the prescription for the next planned set**, which is what the sheet draws
    /// above the fields (`FR-15.3.1`): the seed is the plan applied, and the line is the plan still
    /// legible after the lifter has typed over it.
    ///
    /// **Repeat comes first, and appears only once there is a set to repeat** — a control that
    /// promised to copy nothing being worse than one that is not there yet.
    private var setCommands: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm.points) {
                repeatButton
                addButton
            }
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                repeatButton
                addButton
            }
        }
    }

    /// `FR-1.2.6`'s duplicate — the editor opened over the last set logged on this card, wherever
    /// it sat. See ``ActiveSessionStore/logNextSet(inEntryID:copying:)`` for how the two differ.
    @ViewBuilder private var repeatButton: some View {
        if let last = item.sets.last {
            Button {
                logSet(
                    SetEditorTarget(
                        entryID: item.id,
                        values: SetEntryValues(
                            weight: last.weight,
                            reps: last.reps,
                            rpe: last.rpe,
                            isWarmup: last.isWarmup
                        ),
                        prescribed: item.nextPlannedGroup
                    )
                )
            } label: {
                Text(LoggingStrings.setRepeatAction)
            }
            .buttonStyle(.secondaryAction(.fill, touch: .logging))
        }
    }

    /// `FR-1.2.3`'s blank form, which opens filled in where a routine planned this set —
    /// `FR-15.2.3`, and what makes `NFR-15.3`'s two taps reachable at all.
    private var addButton: some View {
        Button {
            logSet(
                SetEditorTarget(
                    entryID: item.id,
                    planned: item.plannedSeed,
                    prescribed: item.nextPlannedGroup
                )
            )
        } label: {
            Text(LoggingStrings.setAddAction)
        }
        .buttonStyle(.secondaryAction(.fill, touch: .logging))
    }

    /// The exercise's name, or a sentence in place of one.
    ///
    /// An entry pointing at a catalogue row that is not there renders as a broken card rather than
    /// as no card: see ``SessionExercise/exercise``.
    private var name: Text {
        guard let exercise = item.exercise else {
            return Text(LoggingStrings.sessionExerciseMissing)
        }
        return Text(verbatim: exercise.displayName(for: locale))
    }
}
