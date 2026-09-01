import AppNavigation
import DesignSystem
import DesignTokens
import Foundation
import RepositoryInterface
import SwiftUI

/// Every routine the lifter has authored (`FR-15.2.1`).
///
/// The view half of `TR-1.2`'s pattern, and the same `ScrollView`/`LazyVStack` shape the Phase 1
/// screens use for the same reason — `TR-1.12`'s harness renders through `ImageRenderer`, which
/// draws a placeholder for anything UIKit-backed.
public struct RoutineListView: View {
    @State private var state: RoutineListState

    /// Starts a workout from one routine, reporting whether a workout is now in progress
    /// (`FR-15.2.3`).
    ///
    /// **A closure the app target supplies**, on `LastWorkoutSection`'s precedent: writing a
    /// session is `Logging`'s and `TR-1.3` keeps the feature packages off each other, so the target
    /// that owns both composes them. Required rather than optional — this screen's primary command
    /// is starting a workout, and a default that did nothing would be a button that silently is not
    /// one.
    private let startWorkout: @MainActor (UUID) async -> Bool

    /// The shell's navigation position: starting a workout lands on Train's session screen, which
    /// is not a push from here.
    @Environment(NavigationState.self) private var navigation: NavigationState?

    /// Builds the screen over the repository it reads through.
    ///
    /// - Parameters:
    ///   - repository: Where routines come from. `Persistence`'s implementation in the app;
    ///     anything conforming in a test or a preview.
    ///   - startWorkout: Starts a workout from the routine it is given (`FR-15.2.3`).
    public init(
        repository: any RoutineRepository,
        startWorkout: @escaping @MainActor (UUID) async -> Bool
    ) {
        _state = State(initialValue: RoutineListState(repository: repository))
        self.startWorkout = startWorkout
    }

    /// The routines, or whichever of the screen's three other states is current.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg.points) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(RoutinesStrings.listTitle))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: Route.routines(.routineCreate)) {
                    Text(RoutinesStrings.listNewRoutine)
                }
            }
        }
        // Re-read on every appearance, not only the first: the editor pushed over this screen is
        // what changes what it lists, and it writes on its way out.
        .task { await state.load() }
    }

    /// The screen's four states (`FR-1.13.1`), each one of T-1.09's shared components.
    ///
    /// **No offline state**, on the argument every local screen makes: the store is on the device
    /// (`G-2.1`, `G-2.3`), so there is no fetch to be offline for. **No insufficient-data state**
    /// either (`FR-1.13.3`) — a routine is what the lifter typed in, not a value derived from
    /// history.
    @ViewBuilder private var content: some View {
        switch state.phase {
        case .idle, .loading:
            LoadingStateView()
        case .failed:
            ErrorStateView(
                headline: Text(RoutinesStrings.listErrorHeadline),
                message: Text(RoutinesStrings.listErrorMessage),
                retry: { Task { await state.load() } }
            )
        case .ready where state.routines.isEmpty:
            // FR-1.13.2: the first-launch empty state carries the action that ends it.
            EmptyStateView(
                symbolName: "list.bullet.rectangle",
                headline: Text(RoutinesStrings.listEmptyHeadline),
                message: Text(RoutinesStrings.listEmptyMessage)
            )
            NavigationLink(value: Route.routines(.routineCreate)) {
                Text(RoutinesStrings.listNewRoutine)
            }
            .buttonStyle(.primaryAction(.fill))
        case .ready:
            if state.startDidFail {
                ErrorStateView(message: Text(RoutinesStrings.listStartErrorMessage))
            }
            LazyVStack(spacing: Spacing.md.points) {
                ForEach(state.routines) { routine in
                    RoutineCard(routine: routine, start: { start(routine.id) })
                }
            }
        }
    }

    /// Starts a workout from `routineID` and opens it (`FR-15.2.3`, `NFR-15.3`).
    ///
    /// **The push happens only when a workout was started**, on `TrainingHomeView`'s rule for the
    /// same command: a refusal leaves the lifter on this screen with the reason beside the routines
    /// rather than on a session screen showing a workout they did not ask for.
    ///
    /// - Parameter routineID: The routine to start from.
    private func start(_ routineID: UUID) {
        Task {
            let started = await startWorkout(routineID)
            state.startDidFinish(started: started)
            guard started else { return }
            navigation?.navigate(to: .training(.activeSession))
        }
    }
}

/// One routine as the list offers it: the plan to edit, and the command that starts a workout from
/// it (`FR-15.2.1`, `FR-15.2.3`).
///
/// **Two controls stacked rather than one row doing both**, and neither nested in the other. A
/// button inside a `NavigationLink` is the classic SwiftUI trap — the outer link swallows the inner
/// tap — and side by side they are two commands sharing a row at `accessibility3`, which is
/// `SessionExerciseCard`'s reason for stacking its own two.
struct RoutineCard: View {
    /// What the card draws.
    let routine: RoutineSummary

    /// Starts a workout from this routine.
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.points) {
            NavigationLink(value: Route.routines(.routineEdit(routineID: routine.id))) {
                RoutineRow(routine: routine)
            }
            .buttonStyle(.plain)
            Button(action: start) {
                Text(RoutinesStrings.listStartAction)
            }
            .buttonStyle(.primaryAction(.fill))
        }
    }
}

/// One routine's row: its name, and how many exercises it prescribes.
struct RoutineRow: View {
    /// What the row draws.
    let routine: RoutineSummary

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md.points) {
                VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                    name
                        .font(Typography.cardTitle.font)
                        .foregroundStyle(ColorToken.textPrimary)
                    Text(RoutinesStrings.listExerciseCount(routine.exerciseCount))
                        .font(Typography.metricContext.font)
                        .foregroundStyle(ColorToken.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
                    // The chevron says "this pushes"; the row's own two lines are what VoiceOver
                    // reads, and a glyph announced beside them is noise (`G-4.2`).
                    .accessibilityHidden(true)
            }
            .frame(minHeight: TouchTarget.standard.points, alignment: .leading)
        }
        // One element, not three: a row is one destination (`G-4.2`).
        .accessibilityElement(children: .combine)
    }

    /// The row's title — the lifter's own name for the routine, or the sentence standing in for
    /// one that is empty.
    ///
    /// **A `Text` rather than a `LocalizedStringResource`**, because only one of the two is copy:
    /// the stored name is the user's words and must never be looked up in a catalogue, while the
    /// stand-in is this module's and must be. The editor refuses to save an empty name, so the
    /// stand-in is what a row written by something else gets rather than a case this app produces.
    private var name: Text {
        routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Text(RoutinesStrings.listUnnamed)
            : Text(verbatim: routine.name)
    }
}
