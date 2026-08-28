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

    /// Which exercises the dashboard tiles an estimated max for (`FR-1.9.1`).
    ///
    /// **Pushed rather than presented**, unlike the editors elsewhere that have no case: this screen
    /// holds no unsaved draft — every tick is written straight through — so it is a place the app can
    /// legitimately be restored to.
    ///
    /// It carries no selection, for ``ExerciseLibraryRoute/exerciseDetail(exerciseID:)``'s reason: a
    /// restored stack is decoded before any store has been read, and what is tiled is a stored row
    /// rather than a parameter of a push.
    case estimatedMaxExercises
}

/// Destinations pushed while logging (`FR-1.2`).
public enum TrainingRoute: Hashable, Sendable, Codable {
    /// The workout in progress (`FR-1.2.1`). T-1.20 builds it.
    case activeSession
}

/// Destinations pushed from the exercise library (`FR-1.1`).
public enum ExerciseLibraryRoute: Hashable, Sendable, Codable {
    /// The catalogue, grouped by movement, with search and filters (`FR-1.1.1`, `FR-1.1.2`).
    ///
    /// **Pushed onto Train's stack rather than being Train's root**, which is the answer to the
    /// question ``NavigationState/startWorkout()`` leaves open: the root is the session surface, so
    /// Home's primary action lands on a workout and not on a catalogue. The library is a place the
    /// user goes from there.
    case exerciseList

    /// One exercise's detail (`FR-1.1.6`). T-1.11 builds it.
    ///
    /// The route carries the identifier and not the exercise: a restored stack is decoded before
    /// any store has been read, and a route holding a stale copy of a row would be a second source
    /// of truth for it (`G-1.4`).
    case exerciseDetail(exerciseID: UUID)

    /// The form that authors a new custom exercise (`FR-1.1.3`).
    ///
    /// **A case of its own rather than ``exerciseEdit(exerciseID:)`` with no identifier.** An
    /// optional payload would make one case mean two screens — one that reads a record and one that
    /// cannot — and the inventory keys off the case, so the screen with no route case is the screen
    /// nothing lists.
    case exerciseCreate

    /// The form that edits an existing exercise, built-in ones included (`FR-1.1.4`).
    ///
    /// Carries the identifier and not the record, for the reason ``exerciseDetail(exerciseID:)``
    /// gives.
    case exerciseEdit(exerciseID: UUID)

    /// The catalogue as a chooser, for adding an exercise to the workout in progress (`FR-1.2.2`).
    ///
    /// **The library's route rather than logging's, and pushed rather than presented.** The screen
    /// is ``exerciseList``'s in a second mode — same rows, same search, same filters — so it belongs
    /// to the area that owns those. Pushing it also keeps `Logging` from depending on
    /// `ExerciseLibrary` to reach it (`TR-1.3`): the app target composes the two, handing the
    /// catalogue screen a closure that writes into the session, exactly as it composes every other
    /// screen over a repository.
    ///
    /// **It carries no session identifier**, for ``TrainingRoute/activeSession``'s reason: which
    /// workout is being logged is one fact about the app rather than a parameter of a push. A
    /// restored stack that opens here with no workout in progress therefore lands on a chooser whose
    /// selection has nowhere to go: the row is refused silently, and the screen it pops back to is
    /// already the one saying there is no workout to add to. Nothing is reported here because
    /// nothing was lost, and a diagnostic would land on a screen the user is leaving.
    case exercisePicker
}

/// Destinations pushed from history (`FR-1.5`).
public enum HistoryRoute: Hashable, Sendable, Codable {
    /// One past session (`FR-1.2.7`, `FR-1.2.9`). T-1.39 builds it.
    case session(sessionID: UUID)

    /// A month grid of the days training was logged on (`FR-1.5.3`).
    ///
    /// **It carries no month**, deliberately: which month is on screen is a place the user scrolled
    /// to rather than a place the app can be restored to, and a route holding one would make every
    /// tap on the back-and-forward chevrons a stack edit. A restored stack opens this screen on the
    /// current month, the same as a fresh push does.
    ///
    /// **Nor does it carry the selected day.** Selecting a day reveals that day's sessions beneath
    /// the grid rather than pushing a screen — the sessions are ``session(sessionID:)``'s, and this
    /// is the step that says *which one* where a day holds two.
    case calendar
}

/// Destinations pushed from settings (`FR-1.10`).
public enum SettingsRoute: Hashable, Sendable, Codable {
    /// About, version, acknowledgements, privacy (`FR-1.10.5`). T-1.63 builds it.
    case about

    /// The gyms — bar, collars and plate inventory, one of them in use (`FR-1.10.3`, `FR-1.4.2`,
    /// `FR-1.4.3`).
    ///
    /// **Settings' route over a screen the logging module owns**, which is this enum's tab rule
    /// doing exactly what it is for: `FR-1.10.3` puts equipment management under Settings and
    /// `FR-1.4.2` reaches the same screen from the plate calculator, so the route names the tab and
    /// the app target composes whichever module's screen answers it — see
    /// ``ExerciseLibraryRoute/exercisePicker`` for the other half of the same argument.
    ///
    /// **The editor over one gym has no case**, deliberately: it is a form holding an unsaved draft,
    /// which is not a place the app can be restored to.
    case equipmentProfiles

    /// The bodyweight log — every reading and the seven-day average over them (`FR-1.8.1`,
    /// `FR-1.8.3`).
    ///
    /// **Settings' route over a log that is not a preference**, which is `D-8` rather than an
    /// oversight: the four tabs are fixed and none of them is the body log, so the row that opens it
    /// sits beside the gyms — where `FR-1.10.4`'s HealthKit permission also lands, and Health is
    /// where the same log's other readings will come from.
    ///
    /// **The form over one reading has no case**, for ``equipmentProfiles``' reason.
    case bodyweight

    /// What Health access the app has, and the way out to where it is changed (`FR-1.10.4`).
    ///
    /// **A screen of its own rather than a row on the landing**, because it is mostly an
    /// explanation: iOS discloses no read grant, so what this destination holds is the sentence
    /// saying why the status it shows is not one — which is more than a settings row can carry.
    case healthAccess
}
