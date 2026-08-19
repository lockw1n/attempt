import AppNavigation
import DesignSystem
import PowerliftingCore
import RepositoryInterface

/// Preferences, data portability and sync (`FR-1.10`, `FR-1.11`, `FR-1.12`).
///
/// A namespace and nothing else, its four aliases pinning the module's dependency surface
/// (`TR-1.3`) until the screens land — the argument is in `ExerciseLibraryModule`.
public enum SettingsModule {
    typealias Storage = SettingsRepository
    typealias Domain = Weight
    typealias Destination = SettingsRoute
    typealias Tokens = ColorToken
}
