import DesignSystem
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// Which of the exercise list's states is current (`FR-1.13.1`).
///
/// A value rather than a chain of `if`s, for ``TrainingHomeState``'s reason — and for a second one
/// here: the store carries two diagnostics for this list, and which of them is being reported is
/// the whole difference between a screen that keeps its cards and one that has none.
enum SessionExercisesState: Equatable {
    /// Nothing has read the workout's exercises yet.
    case loading

    /// The workout has none, with `writeFailed` when the last command against it did not land.
    case empty(writeFailed: Bool)

    /// The workout's exercises, and the same flag.
    case listed([SessionExercise], writeFailed: Bool)

    /// The read failed, so what is in the workout is not known.
    case readFailed

    /// The state to render.
    ///
    /// **A failed read outranks the cards, and a failed write does not.** They are opposite facts: a
    /// read that failed leaves the screen unable to vouch for what is in the workout, so it shows
    /// the state with the retry in it; a write that failed leaves every card exactly as it was, so
    /// it renders beside them and the retry is the command the user reached for.
    ///
    /// - Parameters:
    ///   - hasLoaded: ``ActiveSessionStore/hasLoadedExercises``.
    ///   - exercises: ``ActiveSessionStore/exercises``.
    ///   - readFailure: ``ActiveSessionStore/exercisesReadFailure``.
    ///   - writeFailure: ``ActiveSessionStore/exercisesWriteFailure``.
    /// - Returns: The current state.
    static func current(
        hasLoaded: Bool,
        exercises: [SessionExercise],
        readFailure: String?,
        writeFailure: String?
    ) -> Self {
        if !hasLoaded { return .loading }
        if readFailure != nil { return .readFailed }
        if exercises.isEmpty { return .empty(writeFailed: writeFailure != nil) }
        return .listed(exercises, writeFailed: writeFailure != nil)
    }
}

/// How far through the workout the user is (`FR-1.2.13`).
///
/// **Drawn from two capsules rather than a `ProgressView`.** The system control is UIKit-backed, so
/// `TR-1.12`'s `ImageRenderer` harness rasterises it as a placeholder and the one thing worth a
/// reference here — how full the bar is — would be invisible to the gate. The fill is also not the
/// only cue: the count beside it says the same thing in words (`G-4.5`).
struct SessionProgressHeader: View {
    /// The workout's progress.
    let progress: SessionProgress

    /// The count, then the bar.
    ///
    /// One VoiceOver element, because it is one fact said twice (`G-4.2`).
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.points) {
            Text(LoggingStrings.sessionProgress(completed: progress.completed, total: progress.total))
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            bar
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.lg.points)
        .padding(.vertical, Spacing.md.points)
        .background(ColorToken.surfaceRaised)
        .accessibilityElement(children: .combine)
    }

    /// The track and the fill.
    private var bar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ColorToken.background)
                Capsule()
                    .fill(ColorToken.brandAccent)
                    .frame(width: proxy.size.width * progress.fraction)
            }
        }
        .frame(height: Spacing.sm.points)
        .accessibilityHidden(true)
    }
}

/// The workout's exercises, as `FR-1.2.13`'s vertical list of cards.
///
/// **A `LazyVStack` of cards, never a pager or a `List`.** `FR-1.2.13` bans horizontal tabs
/// outright; the `List` half is the exercise library's reason — `TR-1.12`'s harness renders through
/// `ImageRenderer`, which draws a UIKit-backed control as a placeholder, so a `List` here would take
/// the whole feature out of the snapshot gate along with the `.onMove` that came with it.
///
/// Taking the exercises rather than the store, so the snapshot has a subject that does not read one.
struct SessionExerciseList: View {
    /// The workout's exercises, in order.
    let exercises: [SessionExercise]

    /// Which cards the user has expanded or collapsed by hand, keyed on the entry.
    ///
    /// **A binding into the screen's state, and stored nowhere** (`NFR-1.8` covers logged data, not
    /// what is folded up). Absent an entry, a card follows its exercise: finished ones are collapsed
    /// and the rest are open, which is `FR-1.2.13`'s rule.
    @Binding var expansion: [UUID: Bool]

    /// Which cards' **warmup groups** the user has folded by hand, keyed on the same entry
    /// (`FR-1.2.14`).
    ///
    /// **A second dictionary rather than a second flag in the first**, because the two folds are
    /// independent by requirement: `FR-1.2.14` gives the warmups a collapse of their own, separate
    /// from `FR-1.2.13`'s whole-card one, and a card that is open can have its warmups rolled up or
    /// not. Absent an entry, the group follows the exercise — see ``defaultWarmupExpansion(for:)``.
    @Binding var warmupExpansion: [UUID: Bool]

    /// Moves the named exercise by that many places (`FR-1.2.2`).
    let move: (UUID, Int) -> Void

    /// The unit every load on these cards is shown in (`G-3.1`).
    let unit: MassUnit

    /// Opens the set editor over one exercise (`FR-1.2.3`, `FR-1.2.6`).
    let logSet: (SetEditorTarget) -> Void

    /// Marks one set as a warmup or as working (`FR-1.2.4`) — the set, then which it becomes.
    let mark: (SetEntry, Bool) -> Void

    /// Marks one set as completed or failed (`FR-1.2.5`) — the set, then which it becomes.
    let markCompleted: (SetEntry, Bool) -> Void

    /// One card per entry.
    var body: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.md.points) {
            ForEach(Array(exercises.enumerated()), id: \.element.id) { position, item in
                SessionExerciseCard(
                    item: item,
                    position: position,
                    count: exercises.count,
                    isExpanded: expansion[item.id] ?? !item.isComplete,
                    toggle: { expansion[item.id] = !(expansion[item.id] ?? !item.isComplete) },
                    areWarmupsExpanded: warmupExpansion[item.id] ?? Self.defaultWarmupExpansion(for: item),
                    toggleWarmups: {
                        warmupExpansion[item.id] =
                            !(warmupExpansion[item.id] ?? Self.defaultWarmupExpansion(for: item))
                    },
                    move: move,
                    unit: unit,
                    logSet: logSet,
                    mark: mark,
                    markCompleted: markCompleted
                )
            }
        }
    }

    /// Whether an exercise's warmups are shown, before the user has said either way.
    ///
    /// **Open until the work starts, folded once it has**, which is `FR-1.2.13`'s card rule applied
    /// one level down rather than a second convention: a finished exercise folds, and warmups are
    /// finished the moment the first working set is logged. Mid-ramp the numbers being checked are
    /// the warmups themselves; after it, they are three rows of noise above the work.
    ///
    /// **It folds upwards, which makes it safe for the set that triggers it and unsafe for a set
    /// written into it.** The group sits *above* the working sets, so the first working set folding
    /// it pulls that row towards the thumb rather than taking it off screen. A set written into the
    /// group while it is folded — logged as a warmup, or marked as one afterwards — is the other
    /// case, and the screen overrides this default for both: see `ActiveSessionView`.
    ///
    /// - Parameter item: The exercise.
    /// - Returns: Whether its warmup group starts open.
    static func defaultWarmupExpansion(for item: SessionExercise) -> Bool {
        !item.hasWorkingSets
    }
}

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

    /// Moves the named exercise by that many places (`FR-1.2.2`).
    let move: (UUID, Int) -> Void

    /// The unit this card's loads are shown in (`G-3.1`).
    let unit: MassUnit

    /// Opens the set editor over this exercise (`FR-1.2.3`, `FR-1.2.6`).
    let logSet: (SetEditorTarget) -> Void

    /// Marks one of this card's sets as a warmup or as working (`FR-1.2.4`).
    let mark: (SetEntry, Bool) -> Void

    /// Marks one of this card's sets as completed or failed (`FR-1.2.5`).
    let markCompleted: (SetEntry, Bool) -> Void

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
                        if item.isComplete {
                            Text(LoggingStrings.sessionExerciseCompleted)
                                .font(Typography.caption.font)
                                .foregroundStyle(ColorToken.positive)
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

    /// What the card holds while it is open: the sets logged against it, and the two ways to add one.
    ///
    /// **An empty card says so in a sentence rather than in one of `FR-1.13.1`'s states.** Zero sets
    /// is a count the same way three is, and a state placeholder per card would be five of them down
    /// a workout.
    private var contents: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.points) {
            if item.sets.isEmpty {
                Text(LoggingStrings.setListEmpty)
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.textSecondary)
            } else {
                warmupGroup
                ForEach(workingSets) { row(for: $0) }
            }
            setCommands
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
                ForEach(warmups) { row(for: $0) }
            }
        }
    }

    /// One set's row, wherever on the card it is drawn.
    ///
    /// - Parameter numbered: The set and its number.
    /// - Returns: The row.
    private func row(for numbered: NumberedSet) -> some View {
        SetRow(numbered: numbered, unit: unit, mark: mark, markCompleted: markCompleted)
    }

    /// This card's sets, each carrying its number within its own sequence (`FR-1.2.14`).
    private var numberedSets: [NumberedSet] { SetNumbering.numbered(item.sets) }

    /// The warmups among them, in the order they were logged.
    private var warmups: [NumberedSet] { numberedSets.filter(\.isWarmup) }

    /// The work proper, likewise.
    private var workingSets: [NumberedSet] { numberedSets.filter { !$0.isWarmup } }

    /// `FR-1.2.6`'s duplicate, then `FR-1.2.3`'s blank form.
    ///
    /// **Stacked rather than side by side**, which is `NFR-1.10` rather than taste: two commands
    /// sharing a row at `accessibility3` are two commands with three characters each.
    ///
    /// **Repeat is the filled one and comes first.** It is the dominant logging action — the whole
    /// of `NFR-1.3`'s three taps is spent here — and it appears only once there is a set to repeat,
    /// a control that promised to copy nothing being worse than one that is not there yet.
    private var setCommands: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.points) {
            if let last = item.sets.last {
                Button {
                    logSet(
                        SetEditorTarget(
                            entryID: item.id,
                            repeating: SetEntryValues(
                                weight: last.weight,
                                reps: last.reps,
                                rpe: last.rpe,
                                isWarmup: last.isWarmup
                            )
                        )
                    )
                } label: {
                    Text(LoggingStrings.setRepeatAction)
                }
                .buttonStyle(.primaryAction(.fill))
            }
            Button {
                logSet(SetEditorTarget(entryID: item.id, repeating: nil))
            } label: {
                Text(LoggingStrings.setAddAction)
                    .font(Typography.actionLabel.font)
                    .foregroundStyle(ColorToken.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.logging.points)
                    .background(
                        ColorToken.surface,
                        in: .rect(cornerRadius: CornerRadius.control.points)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    /// The exercise's name, or a sentence in place of one.
    ///
    /// An entry pointing at a catalogue row that is not there renders as a broken card rather than
    /// as no card: see ``SessionExercise/exercise``.
    private var name: Text {
        guard let exercise = item.exercise else {
            return Text(LoggingStrings.sessionExerciseMissing)
        }
        return Text(verbatim: exercise.name)
    }
}
