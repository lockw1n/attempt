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

    /// Which set groups the user has opened (`FR-16.1.3`), keyed on the group — which is its first
    /// set's id.
    ///
    /// **One set across the whole workout rather than a dictionary per card**, because the key is a
    /// set's identifier and those are unique across every card in it. Absent, a group is collapsed:
    /// `FR-16.1.1`'s whole point is that four identical sets read as one line until asked.
    @Binding var groupExpansion: Set<UUID>

    /// Moves the named exercise by that many places (`FR-1.2.2`).
    let move: (UUID, Int) -> Void

    /// The unit every load on these cards is shown in (`G-3.1`).
    let unit: MassUnit

    /// What each card's `FR-1.2.10` strip is drawn from, keyed on the entry.
    ///
    /// **The whole map rather than one lookup per card**, because the answer is one read: a card
    /// handed a closure could not tell "not read yet" from "never trained" without asking the store
    /// itself, which is the thing a snapshot has none of.
    let previous: PreviousPerformances

    /// Which of the workout's sets hold a record (`FR-1.6.3`), keyed on the set.
    ///
    /// The whole map rather than one lookup per card, for ``previous``' reason: one read answers
    /// every card, and a card handed a closure could not be snapshotted.
    let personalRecords: SessionRecordMarks

    /// Opens the set editor over one exercise (`FR-1.2.3`, `FR-1.2.6`).
    let logSet: (SetEditorTarget) -> Void

    /// Marks one set as a warmup or as working (`FR-1.2.4`) — the set, then which it becomes.
    let mark: (SetEntry, Bool) -> Void

    /// Marks one set as completed or failed (`FR-1.2.5`) — the set, then which it becomes.
    let markCompleted: (SetEntry, Bool) -> Void

    /// Opens `FR-1.2.7`'s editor over one set.
    let edit: (SetEntry) -> Void

    /// Checks one exercise off, or takes the check back (`FR-15.3.4`) — the entry, then which it
    /// becomes.
    let markDone: (UUID, Bool) -> Void

    /// Logs the next planned set exactly as prescribed (`NFR-15.3`) — the entry.
    let logPlanned: (UUID) -> Void

    /// One card per entry.
    var body: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.md.points) {
            ForEach(Array(exercises.enumerated()), id: \.element.id) { position, item in
                SessionExerciseCard(
                    item: item,
                    position: position,
                    count: exercises.count,
                    isExpanded: expansion[item.id] ?? !item.isDone,
                    toggle: { expansion[item.id] = !(expansion[item.id] ?? !item.isDone) },
                    areWarmupsExpanded: warmupExpansion[item.id] ?? Self.defaultWarmupExpansion(for: item),
                    toggleWarmups: {
                        warmupExpansion[item.id] =
                            !(warmupExpansion[item.id] ?? Self.defaultWarmupExpansion(for: item))
                    },
                    expandedGroups: groupExpansion,
                    toggleGroup: { setID in
                        if groupExpansion.contains(setID) {
                            groupExpansion.remove(setID)
                        } else {
                            groupExpansion.insert(setID)
                        }
                    },
                    move: move,
                    unit: unit,
                    previous: previous.state(forEntryID: item.id),
                    personalRecords: personalRecords,
                    logSet: logSet,
                    mark: mark,
                    markCompleted: markCompleted,
                    edit: edit,
                    markDone: markDone,
                    logPlanned: logPlanned
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
