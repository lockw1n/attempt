import AppNavigation
import DesignSystem
import PowerliftingCore
import RepositoryInterface

/// Past training (`FR-1.5`) — the session list, per-exercise history, the calendar and search.
///
/// A namespace and nothing else, its four aliases pinning the module's dependency surface
/// (`TR-1.3`) until the screens land — the argument is in `ExerciseLibraryModule`.
public enum HistoryModule {
    typealias Storage = WorkoutRepository
    typealias Domain = Weight
    typealias Destination = HistoryRoute
    typealias Tokens = ColorToken
}
