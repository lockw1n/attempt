import AppNavigation
import DesignSystem
import PowerliftingCore
import RepositoryInterface

/// Workout logging (`FR-1.2`) — the active session and everything logged into it.
///
/// A namespace and nothing else, its four aliases pinning the module's dependency surface
/// (`TR-1.3`) until the screens land — the argument is in `ExerciseLibraryModule`.
public enum LoggingModule {
    typealias Storage = WorkoutRepository
    typealias Domain = Weight
    typealias Destination = TrainingRoute
    typealias Tokens = ColorToken
}
