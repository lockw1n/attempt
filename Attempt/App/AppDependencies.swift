import Persistence
import RepositoryInterface

/// The live objects the app is built over, opened once at launch (`TR-0.1`, `G-2.2`).
///
/// This target is the only one that may name `Persistence`: a feature reaches storage through a
/// repository protocol and never through the module that implements one (`TR-0.1.2`), so the store
/// is opened here and the five existentials are handed down.
///
/// **A store that will not open is carried rather than thrown**, because there is nothing above
/// this to catch it: the alternative at launch is a crash with no explanation for the user and no
/// diagnostic for anyone else. What a screen shows in that case is scaffolding until a task owns
/// the launch failure surface.
struct AppDependencies {
    /// The five repositories, or `nil` if the store could not be opened.
    ///
    /// **Private, and handed out one protocol at a time below.** `PersistenceStack` is the only
    /// type in this app that names `Persistence`'s module in its own signature, so a view that
    /// took the stack would have to import that module to say so — and the rule this file states
    /// would then hold in one file fewer for every screen that lands.
    private let repositories: PersistenceStack?

    /// The single settings row, or `nil` if the store could not be opened.
    var settings: (any SettingsRepository)? { repositories?.settings }

    /// Why the store could not be opened, as the error's description, or `nil`.
    ///
    /// A diagnostic, not copy (`G-3.4`).
    let storeFailure: String?

    /// Opens the store at `location`.
    ///
    /// - Parameter location: `.applicationDefault` for the app; `.inMemory` is what a preview wants.
    init(location: StoreLocation = .applicationDefault) {
        do {
            repositories = try PersistenceStack(location: location)
            storeFailure = nil
        } catch {
            repositories = nil
            storeFailure = String(describing: error)
        }
    }

    /// An empty store that is never written to disk — what a preview wants, and the reason
    /// ``init(location:)`` takes a location at all.
    static var preview: AppDependencies { AppDependencies(location: .inMemory) }
}
