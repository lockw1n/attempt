import DesignSystem
import Localization
import RepositoryInterface
import SwiftUI

/// The workout in progress (`FR-1.2.11`, `FR-1.2.12`).
///
/// **The lifecycle screen, not yet the logging one.** What is here is the workout itself — the day
/// it belongs to, when it started, and the two ways it ends. Its exercises and their sets are
/// T-1.21's onwards, and the empty state below is the space they land in rather than a placeholder
/// for them.
///
/// **It carries no identifier, and that is why ``ActiveSessionStore`` exists.** `TrainingRoute` has
/// no payload for this screen: the workout in progress is one fact about the app, not a parameter of
/// a push, so a restored navigation stack that opens straight onto this screen shows whichever
/// workout the store found — or says there is none, which is what a stack restored after the workout
/// was finished has to say.
public struct ActiveSessionView: View {
    private let store: ActiveSessionStore

    /// The way back to the root once the workout has ended, one way or the other.
    @Environment(\.dismiss) private var dismiss

    /// Whether `FR-1.2.12`'s confirmation is on screen.
    ///
    /// The screen's and not the store's: a dialogue the user has open is not a fact about the
    /// workout, and it must not survive the screen being left.
    @State private var isConfirmingDiscard = false

    /// Builds the screen over the store that holds the workout.
    ///
    /// - Parameter store: The workout in progress. One per app, built where the repositories are.
    public init(store: ActiveSessionStore) {
        self.store = store
    }

    /// The workout, or whichever of the screen's other states is current.
    ///
    /// `.task` calls ``ActiveSessionStore/resume()`` for the restored-stack case: this screen can be
    /// the first thing the app draws, and it must not announce that there is no workout while the
    /// read that would find one has not run. The call is idempotent — a workout already held is kept
    /// and nothing is read.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl.points) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(LoggingStrings.sessionTitle))
        .task { await store.resume() }
        .confirmationDialog(
            Text(LoggingStrings.sessionDiscardConfirmTitle),
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await discard() }
            } label: {
                Text(LoggingStrings.sessionDiscardConfirmAction)
            }
            Button(role: .cancel) {
            } label: {
                Text(LoggingStrings.sessionDiscardConfirmCancel)
            }
        } message: {
            Text(LoggingStrings.sessionDiscardConfirmMessage)
        }
    }

    /// The screen's three states (`FR-1.13.1`), each one of T-1.09's shared components.
    ///
    /// **"No workout in progress" is an error state without a retry**, on the exercise detail
    /// screen's precedent for an identifier that resolves to nothing: reading again resolves to the
    /// same absence, so a retry would be a button that re-answers the same way. It is not an empty
    /// state either — the empty one below belongs to a workout that exists and has nothing in it,
    /// and rendering "no exercises yet" for a workout that is gone would offer to log into nothing.
    ///
    /// No offline and no insufficient-data state, for `TrainingHomeView`'s reasons.
    @ViewBuilder private var content: some View {
        if !store.hasCheckedForSession {
            LoadingStateView()
        } else if let session = store.session {
            loaded(session)
        } else {
            ErrorStateView(
                headline: Text(LoggingStrings.sessionEndedHeadline),
                message: Text(LoggingStrings.sessionEndedMessage)
            )
        }
    }

    /// A workout that is in progress: what it is, what is in it, and the two ways out.
    @ViewBuilder private func loaded(_ session: WorkoutSession) -> some View {
        SessionSummarySection(session: session)
        EmptyStateView(
            symbolName: "list.bullet.rectangle",
            headline: Text(LoggingStrings.sessionEmptyHeadline),
            message: Text(LoggingStrings.sessionEmptyMessage)
        )
        SessionCommandsSection(
            hasFailed: store.failure != nil,
            finish: { Task { await finish() } },
            discard: { isConfirmingDiscard = true }
        )
    }

    /// Finishes the workout and leaves the screen, unless the write failed.
    ///
    /// The screen stays open on a failure, with the workout still on it: nothing was stored, so the
    /// retry is another tap at the same command rather than a workout the user has to find again.
    private func finish() async {
        await store.finish()
        guard !store.isActive else { return }
        dismiss()
    }

    /// Discards the workout and leaves the screen, unless the write failed. See ``finish()``.
    private func discard() async {
        await store.discard()
        guard !store.isActive else { return }
        dismiss()
    }
}

/// The workout's own facts.
///
/// Taking the record rather than the store, for `SessionInProgressSection`'s reason.
struct SessionSummarySection: View {
    /// The workout being logged.
    let session: WorkoutSession

    /// Which locale the day and the time are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The training day, and when the workout was started.
    var body: some View {
        GroupedSection(Text(LoggingStrings.sessionSummarySection)) {
            SessionFactRow(
                label: LoggingStrings.sessionDay,
                value: Text(session.date, format: AppFormat.date(locale: locale))
            )
            if let startedAt = session.startedAt {
                SessionFactRow(
                    label: LoggingStrings.sessionStarted,
                    value: Text(startedAt, format: AppFormat.dateAndTime(locale: locale))
                )
            }
        }
    }
}

/// The two ways a workout ends (`FR-1.2.11`, `FR-1.2.12`).
///
/// Taking closures rather than the store, so both commands are picturable without one behind them.
///
/// **Finish is the primary action and discard is not styled as one.** They are not two options: one
/// keeps the workout and one throws it away, and a pair of matching buttons is how the second gets
/// tapped by accident. `FR-1.2.12`'s confirmation is the other half of that, and it is the caller's.
struct SessionCommandsSection: View {
    /// Whether the last write failed. The workout is unchanged when it did, so both commands still
    /// ask for the same thing and the retry is the same tap.
    let hasFailed: Bool

    /// Ends the workout and keeps it.
    let finish: () -> Void

    /// Asks whether to throw it away.
    let discard: () -> Void

    /// Both commands, and a failed write beneath them.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md.points) {
            Button(action: finish) {
                Text(LoggingStrings.sessionFinishAction)
            }
            .buttonStyle(.primaryAction(.fill))

            Button(action: discard) {
                Text(LoggingStrings.sessionDiscardAction)
                    .font(Typography.actionLabel.font)
                    .foregroundStyle(ColorToken.negative)
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
            }
            .buttonStyle(.plain)

            if hasFailed {
                // The shared error component rather than a local label, and the workout stays on
                // screen beside it — a failed write costs this screen nothing.
                ErrorStateView(message: Text(LoggingStrings.sessionWriteErrorMessage))
            }
        }
    }
}
