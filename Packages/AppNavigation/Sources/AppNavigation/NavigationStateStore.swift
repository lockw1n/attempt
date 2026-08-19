import Foundation

/// Where a ``NavigationSnapshot`` is kept between launches (`TR-1.1`).
///
/// A protocol because the app's own storage is `UserDefaults` and a test's is not — and because
/// what "restoration" means is a policy: this one keeps the last position indefinitely. Reads never
/// throw; unreadable stored bytes are indistinguishable from none, which is the degrade rule
/// ``NavigationSnapshot`` states.
public protocol NavigationStateStore {
    /// The stored position, or `nil` if there is none this version can read.
    func load() -> NavigationSnapshot?

    /// Stores `snapshot`, replacing whatever was there.
    func save(_ snapshot: NavigationSnapshot)
}

/// The app's store: one JSON blob in `UserDefaults`.
///
/// `UserDefaults` rather than a file, because the payload is a few dozen bytes of position that must
/// be written on every push and read before the first frame.
public struct UserDefaultsNavigationStateStore: NavigationStateStore {
    private let defaults: UserDefaults
    private let key: String

    /// Creates a store.
    ///
    /// - Parameters:
    ///   - defaults: The defaults to read and write. A test passes its own suite.
    ///   - key: The defaults key. Versioned, so a future shape that cannot degrade into this one
    ///     can be given its own key rather than having to be readable from these bytes.
    public init(defaults: UserDefaults = .standard, key: String = "navigation.snapshot.v1") {
        self.defaults = defaults
        self.key = key
    }

    /// The stored position. Unreadable bytes are reported as none, never as a default position.
    public func load() -> NavigationSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(NavigationSnapshot.self, from: data)
    }

    /// Stores `snapshot`. A snapshot that cannot be encoded leaves the previous one in place.
    public func save(_ snapshot: NavigationSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
