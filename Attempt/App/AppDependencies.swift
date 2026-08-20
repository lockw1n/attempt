import Logging
import Persistence
import RepositoryInterface
import SeedImport

/// The live objects the app is built over, opened once at launch (`TR-0.1`, `G-2.2`).
///
/// This target is the only one that may name `Persistence`: a feature reaches storage through a
/// repository protocol and never through the module that implements one (`TR-0.1.2`), so the store
/// is opened here and the repositories are handed down one protocol at a time.
///
/// **A store that will not open is carried rather than thrown**, because there is nothing above
/// this to catch it: the alternative at launch is a crash with no explanation for the user and no
/// diagnostic for anyone else. What a screen shows in that case is scaffolding until a task owns
/// the launch failure surface.
struct AppDependencies {
    /// The repositories a screen reads through, one protocol each.
    ///
    /// **Not `PersistenceStack` itself.** That type names `Persistence`'s module in its own
    /// signature, so a view that took the stack would have to import that module to say so — and
    /// the rule this file states would then hold in one file fewer for every screen that lands.
    /// Screens are added here as they arrive; today one has.
    struct Repositories {
        /// The single settings row.
        let settings: any SettingsRepository

        /// The exercise catalogue (`FR-1.1`).
        let exercises: any ExerciseRepository

        /// Sessions, the exercises in them and their sets (`FR-1.2`).
        let workouts: any WorkoutRepository
    }

    /// The app-lifetime stores (`TR-1.2`), built over the repositories beside them.
    ///
    /// **Two of these exist by rule and not by taste.** `TR-1.2` allows a store exactly where a
    /// piece of state outlives every screen that shows it; everything else is a screen's own
    /// `@Observable`, created with the screen. Both of the ones here are the workout in progress
    /// seen from two sides — the session itself, and the preference that decides whether the screen
    /// sleeps while one is on (`NFR-1.9`).
    ///
    /// They travel with ``Repositories`` in the same case rather than beside it, because there is no
    /// state in which one exists and the other does not: a store is built over a repository, and a
    /// repository comes from a store that opened.
    struct Stores {
        /// The workout in progress (`FR-1.2.1`, `FR-1.2.11`, `FR-1.2.12`).
        let activeSession: ActiveSessionStore

        /// Whether the screen is held awake during one (`NFR-1.9`).
        let screenWake: ScreenWakePreference
    }

    /// The opened store's repositories, or why the store could not be opened.
    ///
    /// **One value rather than a pair of optionals**, because the two are the same fact: an
    /// optional stack beside an optional diagnostic makes "no repositories and no reason" a state
    /// a caller has to handle and this initializer cannot produce.
    ///
    /// The failed case carries the error's description — a diagnostic, not copy (`G-3.4`).
    enum State {
        /// The store opened.
        case open(Repositories, Stores)

        /// It did not, and this is why.
        case failed(String)
    }

    /// What the app got when it opened the store.
    let state: State

    /// Opens the store at `location`.
    ///
    /// - Parameter location: `.applicationDefault` for the app; `.inMemory` is what a preview wants.
    init(location: StoreLocation = .applicationDefault) {
        do {
            let stack = try PersistenceStack(location: location)
            state = .open(
                Repositories(
                    settings: stack.settings,
                    exercises: stack.exercises,
                    workouts: stack.workouts
                ),
                Stores(
                    activeSession: ActiveSessionStore(
                        repository: stack.workouts,
                        catalogue: stack.exercises
                    ),
                    screenWake: ScreenWakePreference()
                )
            )
        } catch {
            state = .failed(String(describing: error))
        }
    }

    /// Puts the bundled catalogue into the store (`TR-0.5.1`, `NFR-1.7`).
    ///
    /// **Run on every launch, not on the first one.** The import is a merge: a second run over the
    /// same catalogue writes nothing, and a run over a newer one writes only the rows that moved —
    /// see `SeedImporter`. A "have we seeded yet?" flag would be a second source of truth for a
    /// question the store can already answer, and the one that goes wrong after a restore.
    ///
    /// It reads the app bundle and never the network, which is what makes first launch in airplane
    /// mode a working app rather than an empty one (`NFR-1.7`).
    ///
    /// **A failure is swallowed here, and that is the same open item the failed store is** — no
    /// requirement or task says what launch does with a diagnostic, so there is nothing above this
    /// to act on one. Whichever task takes on the launch-failure surface takes this with it, and
    /// the two shapes it has to take are not the same:
    ///
    /// - `invalidPayload`, raised before a single row is written, leaves the store as it was. On a
    ///   first launch that is an empty catalogue, and what the user sees is the exercise list's
    ///   empty state saying the built-in catalogue has not been loaded.
    /// - **Anything the repository raises, which `SeedImporter` documents and which arrives once
    ///   writing has begun, leaves a PARTIALLY seeded store.** The import is row-by-row, so a save
    ///   that fails on the fortieth entry leaves thirty-nine — and the list renders those as an
    ///   ordinary loaded catalogue, not as an empty state, with nothing saying it is short. The
    ///   next launch finishes the job, because the import is a merge; within the session it is
    ///   invisible.
    ///
    /// The discarded ``SeedImportSummary`` is the same gap from the other side: its four counts are
    /// the only evidence of what the import did.
    func importSeedCatalogue() async {
        guard case .open(let repositories, _) = state else { return }
        // `_ =` rather than a bare `try?`: the summary is `@discardableResult`, but wrapping it in
        // `try?` makes an optional this call did not ask for, and an unused one is an error here.
        _ = try? await SeedImporter(exercises: repositories.exercises).importBundledCatalogue()
    }

    /// An empty store that is never written to disk — what a preview wants, and the reason
    /// ``init(location:)`` takes a location at all.
    static var preview: AppDependencies { AppDependencies(location: .inMemory) }
}
