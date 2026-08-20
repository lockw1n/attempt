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

    /// Moves the named exercise by that many places (`FR-1.2.2`).
    let move: (UUID, Int) -> Void

    /// The unit every load on these cards is shown in (`G-3.1`).
    let unit: MassUnit

    /// Opens the set editor over one exercise (`FR-1.2.3`, `FR-1.2.6`).
    let logSet: (SetEditorTarget) -> Void

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
                    move: move,
                    unit: unit,
                    logSet: logSet
                )
            }
        }
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

    /// Moves the named exercise by that many places (`FR-1.2.2`).
    let move: (UUID, Int) -> Void

    /// The unit this card's loads are shown in (`G-3.1`).
    let unit: MassUnit

    /// Opens the set editor over this exercise (`FR-1.2.3`, `FR-1.2.6`).
    let logSet: (SetEditorTarget) -> Void

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
                ForEach(Array(item.sets.enumerated()), id: \.element.id) { index, set in
                    SetRow(set: set, position: index + 1, unit: unit)
                }
            }
            setCommands
        }
    }

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
                                weight: last.weight, reps: last.reps, rpe: last.rpe)
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

/// One logged set inside an exercise card (`FR-1.2.3`).
///
/// **The number, the load, the repetitions and the rating, in that order and on one line.** A set is
/// read at a glance between efforts, so it is a line rather than a card: what a user is checking is
/// what they did last time, not one set in isolation.
///
/// **The multiplication sign is drawn and hidden from VoiceOver** (`G-4.2`). It is punctuation
/// between two numbers rather than a word, and read aloud it is noise; the two numerals either side
/// carry labels of their own instead, so the row is announced as "Set 1, 102.5 kg, Reps 5".
struct SetRow: View {
    /// The set.
    let set: SetEntry

    /// Its one-based position in the exercise.
    ///
    /// **Passed in rather than read from `SetEntry.order`**, which is zero-based and carries gaps
    /// where a set has been soft-deleted. `FR-1.2.14`'s two independent sequences — warmups apart
    /// from working sets — are T-1.23's, and land here.
    let position: Int

    /// The unit the load is shown in (`G-3.1`).
    let unit: MassUnit

    /// Which locale the numbers are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The line.
    var body: some View {
        HStack(spacing: Spacing.sm.points) {
            Text(position, format: AppFormat.count(locale: locale))
                .font(Typography.numericValue.font)
                .foregroundStyle(ColorToken.textTertiary)
                .accessibilityLabel(Text(LoggingStrings.setPosition(position)))
            Text(set.weight, format: AppFormat.weight(in: unit, locale: locale))
                .font(Typography.numericValue.font)
                .foregroundStyle(ColorToken.textPrimary)
            Image(systemName: "multiply")
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textTertiary)
                .accessibilityHidden(true)
            Text(set.reps, format: AppFormat.count(locale: locale))
                .font(Typography.numericValue.font)
                .foregroundStyle(ColorToken.textPrimary)
                .accessibilityLabel(Text(LoggingStrings.setReps(set.reps)))
            Spacer(minLength: Spacing.sm.points)
            rating
        }
        .frame(minHeight: TouchTarget.standard.points)
        .accessibilityElement(children: .combine)
    }

    /// The rating, where the set carries one.
    @ViewBuilder private var rating: some View {
        if let rpe = set.rpe {
            Text(
                LoggingStrings.setRPE(
                    rpe.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
                )
            )
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
        }
    }
}
