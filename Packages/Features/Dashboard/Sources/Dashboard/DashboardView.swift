import AppNavigation
import DerivedValues
import DesignSystem
import Foundation
import RepositoryInterface
import SwiftUI

/// Home's root: the primary action, the last workout, and `FR-1.9.1`'s estimated-max tiles.
///
/// **The "Start workout" action is a navigation and not a logging surface** (`FR-1.9.4`, `D-8`).
/// `NavigationState.startWorkout()` selects Train and drops it to its root, so the app's primary
/// action always arrives at the one screen a workout is started from — which is the duplication the
/// four-tab decision was taken to remove. It stays on screen while a workout is open, because Train's
/// root is what says a workout is open; the card below is where `FR-1.9.2`'s resume lives.
///
/// The `ScrollView`/`VStack` shape every screen in this app uses rather than a `List`, for
/// `TR-1.12`'s reason: the snapshot harness renders through `ImageRenderer`, which draws a
/// placeholder for anything UIKit-backed.
public struct DashboardView: View {
    /// The app's one recompute actor (`TR-1.6`), which values the tiles.
    private let records: PersonalRecordRecomputer

    /// The catalogue: what the tiles are named after, and what the picker chooses among.
    private let catalogue: any ExerciseRepository

    /// The sessions, for `FR-1.9.2`'s card.
    private let workouts: any WorkoutRepository

    /// The settings row: the tile selection (`FR-1.9.1`) and the display unit (`G-3.1`).
    private let settings: any SettingsRepository

    /// Starts a workout holding a past one's exercises. See ``LastWorkoutSection``.
    private let repeatSession: @MainActor (UUID) async -> Bool

    /// The shell's navigation position, for the primary action — which is a tab selection rather
    /// than a push, so it cannot be a `NavigationLink`.
    ///
    /// Optional and read rather than required, for `TrainingHomeView`'s reason: a preview or a
    /// snapshot has no shell above it.
    @Environment(NavigationState.self) private var navigation: NavigationState?

    /// Builds the dashboard.
    ///
    /// - Parameters:
    ///   - records: The app's one recompute actor.
    ///   - catalogue: The exercises.
    ///   - workouts: The sessions and what is under them.
    ///   - settings: The settings row.
    ///   - repeatSession: Starts a fresh workout holding a past one's exercises, reporting whether
    ///     one is now in progress.
    public init(
        records: PersonalRecordRecomputer,
        catalogue: any ExerciseRepository,
        workouts: any WorkoutRepository,
        settings: any SettingsRepository,
        repeatSession: @escaping @MainActor (UUID) async -> Bool
    ) {
        self.records = records
        self.catalogue = catalogue
        self.workouts = workouts
        self.settings = settings
        self.repeatSession = repeatSession
    }

    /// The action, then the last workout, then the tiles.
    ///
    /// **In that order deliberately.** `FR-1.9.4` calls its action primary, and a primary action
    /// below two cards is one a reader scrolls to; what sits under it is the workout they are in the
    /// middle of, and only then the numbers they came to look at.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl.points) {
                startAction
                LastWorkoutSection(
                    workouts: workouts, catalogue: catalogue, repeatSession: repeatSession)
                EstimatedMaxTilesSection(
                    records: records, catalogue: catalogue, settings: settings)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
    }

    /// `FR-1.9.4`'s primary action.
    private var startAction: some View {
        Button {
            navigation?.startWorkout()
        } label: {
            Text(DashboardStrings.startWorkout)
        }
        .buttonStyle(.primaryAction)
        .frame(maxWidth: .infinity)
    }
}
