import DesignSystem
import Localization
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

    /// Which locale the counts are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

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

    /// Moves the exercise at the first position to the second (`FR-1.2.2`).
    let move: (Int, Int) -> Void

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
                    move: move
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

    /// Moves the exercise at the first position to the second (`FR-1.2.2`).
    let move: (Int, Int) -> Void

    /// Which locale the set count is rendered for (`G-3.4`).
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
            .accessibilityAddTraits(isExpanded ? [.isSelected] : [])
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
                move(position, position - 1)
            }
            moveButton(
                symbolName: "arrow.down",
                label: LoggingStrings.sessionExerciseMoveDown,
                isEnabled: position < count - 1
            ) {
                move(position, position + 1)
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

    /// What the card holds while it is open.
    ///
    /// **A set count rather than the sets**, which is the honest half of this card until T-1.22
    /// builds the other. It is data and not one of `FR-1.13.1`'s states: zero sets is a count the
    /// same way three is, and a state placeholder per card would be five of them down a workout.
    private var contents: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.points) {
            SessionFactRow(
                label: LoggingStrings.sessionExerciseSets,
                value: Text(item.sets.count, format: AppFormat.count(locale: locale))
            )
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
