import AppNavigation
import DesignSystem
import PowerliftingCore
import RepositoryInterface

/// The dashboard (`FR-1.9`) — e1RM tiles, the recent-PR feed and the start-workout action.
///
/// A namespace and nothing else, its four aliases pinning the module's dependency surface
/// (`TR-1.3`) until the screens land — the argument is in `ExerciseLibraryModule`.
public enum DashboardModule {
    typealias Storage = WorkoutRepository
    typealias Domain = Weight
    typealias Destination = DashboardRoute
    typealias Tokens = ColorToken
}
