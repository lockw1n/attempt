import AppNavigation
import DesignSystem
import PowerliftingCore
import RepositoryInterface

/// The exercise library (`FR-1.1`).
///
/// THE EXEMPLAR for the other four feature modules' headers, which point here.
///
/// A namespace and nothing else — the screens are each a later task's. The four aliases are the
/// module's whole dependency surface (`TR-1.3`), spelled out so the manifest's edges are compiled
/// against rather than only declared: each resolves a symbol from a different one of the four
/// dependencies, so dropping an import stops the module compiling. They are scaffolding — each is
/// replaced by real use as the screens land, and the last one to go takes this type with it.
public enum ExerciseLibraryModule {
    typealias Storage = ExerciseRepository
    typealias Domain = Weight
    typealias Destination = ExerciseLibraryRoute
    typealias Tokens = ColorToken
}
