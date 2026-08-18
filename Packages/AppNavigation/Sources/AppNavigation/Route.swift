import Foundation

/// Every destination the app can push, namespaced by the feature area that owns it (`TR-1.1`).
///
/// **One enum, not one per tab.** A screen reachable from two tabs — an exercise's detail, from the
/// library under Train and from a session under History — would otherwise have to exist as a case
/// in both, which reintroduces inside the type the duplication a typed route exists to remove. What
/// four enums would have bought, a compiler refusing a Settings route on History's stack, is bought
/// instead by ``tab``: a route names the tab that owns it, and ``NavigationState/navigate(to:)``
/// selects that tab rather than pushing onto whichever one happens to be open.
///
/// **Cases are added by the feature task that builds the screen**, not here. Each sub-enum below
/// carries the one destination its area is certain to have, so the shape is exercisable and
/// `TR-1.13`'s screen inventory has a single source to be derived from.
///
/// **The case names and the associated-value labels are the persisted format** — a stored stack is
/// written as those spellings — so renaming one is a migration, not a rename, and costs every
/// stored stack that names it.
///
/// A stored route this version cannot decode **throws**, which is the closed-vocabulary answer: the
/// set of routes is closed by the binary, and nothing upstream re-supplies a navigation position.
/// ``NavigationSnapshot`` is where that throw is turned into a behaviour.
public enum Route: Hashable, Sendable, Codable {
    /// A destination under Home.
    case dashboard(DashboardRoute)

    /// A destination under Train that belongs to logging.
    case training(TrainingRoute)

    /// A destination under Train that belongs to the exercise library.
    case exerciseLibrary(ExerciseLibraryRoute)

    /// A destination under History.
    case history(HistoryRoute)

    /// A destination under Settings.
    case settings(SettingsRoute)

    /// The tab whose stack this route belongs on.
    ///
    /// Two areas answer `train`, which is Q-1.2's split rather than an accident: logging and the
    /// exercise library are separate feature modules (`TR-1.3`) sharing one tab.
    public var tab: AppTab {
        switch self {
        case .dashboard: .home
        case .training, .exerciseLibrary: .train
        case .history: .history
        case .settings: .settings
        }
    }
}

/// Destinations pushed from the dashboard (`FR-1.9`).
public enum DashboardRoute: Hashable, Sendable, Codable {
    /// The full recent-PRs list behind the dashboard's feed (`FR-1.9.3`). T-1.42 builds it.
    case recentPersonalRecords
}

/// Destinations pushed while logging (`FR-1.2`).
public enum TrainingRoute: Hashable, Sendable, Codable {
    /// The workout in progress (`FR-1.2.1`). T-1.20 builds it.
    case activeSession
}

/// Destinations pushed from the exercise library (`FR-1.1`).
public enum ExerciseLibraryRoute: Hashable, Sendable, Codable {
    /// One exercise's detail (`FR-1.1.6`). T-1.11 builds it.
    ///
    /// The route carries the identifier and not the exercise: a restored stack is decoded before
    /// any store has been read, and a route holding a stale copy of a row would be a second source
    /// of truth for it (`G-1.4`).
    case exerciseDetail(exerciseID: UUID)
}

/// Destinations pushed from history (`FR-1.5`).
public enum HistoryRoute: Hashable, Sendable, Codable {
    /// One past session (`FR-1.5.1`). T-1.35 builds it.
    case session(sessionID: UUID)
}

/// Destinations pushed from settings (`FR-1.10`).
public enum SettingsRoute: Hashable, Sendable, Codable {
    /// About, version, acknowledgements, privacy (`FR-1.10.5`). T-1.63 builds it.
    case about
}
