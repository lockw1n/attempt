import Persistence
import RepositoryInterface

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
        case open(Repositories)

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
            state = .open(Repositories(settings: stack.settings))
        } catch {
            state = .failed(String(describing: error))
        }
    }

    /// An empty store that is never written to disk — what a preview wants, and the reason
    /// ``init(location:)`` takes a location at all.
    static var preview: AppDependencies { AppDependencies(location: .inMemory) }
}
