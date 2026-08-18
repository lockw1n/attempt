import AppNavigation
import DesignSystem
import PowerliftingCore
import RepositoryInterface

/// Past training (`FR-1.5`) — the session list, per-exercise history, the calendar and search.
///
/// A namespace and nothing else — the screens are each a later task's. The four aliases are the
/// module's whole dependency surface (`TR-1.3`), spelled out so the manifest's edges are compiled
/// against rather than only declared, and so the module has a public symbol before its first view
/// does. They are scaffolding: each is replaced by real use as the screens land, and the last one
/// to go takes this type with it.
public enum HistoryModule {
    typealias Storage = WorkoutRepository
    typealias Domain = Weight
    typealias Destination = HistoryRoute
    typealias Tokens = ColorToken
}
