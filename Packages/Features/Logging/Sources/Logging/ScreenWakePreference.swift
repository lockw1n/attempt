import Foundation
import RepositoryInterface

/// Whether the screen is held awake while a workout is being logged (`NFR-1.9`).
///
/// **The decision is here and the mechanism is not.** Turning the idle timer off is `UIApplication`'s
/// and belongs to the app target; what this owns is the one boolean the user controls and the rule
/// that combines it with whether a workout is in progress — which is the half worth a test.
///
/// **Told, not asked, and the stored value is the settings row's** (`UserSettings.keepScreenAwake`).
/// The preference is set on the Settings screen, in another module that cannot reach this one, so
/// the app target seeds this at launch and tells it again on every write. Holding a repository here
/// instead would give one preference two writers, and the settings screen's own write chain exists
/// precisely because two writers rebuild the same row from the same stale read.
@Observable
public final class ScreenWakePreference {
    /// Whether the user wants the screen kept awake during a workout.
    public private(set) var isEnabled: Bool

    /// Starts at `NFR-1.9`'s default until the stored row is read.
    ///
    /// - Parameter isEnabled: What to assume until the row arrives.
    public init(isEnabled: Bool = UserSettings.defaultKeepScreenAwake) {
        self.isEnabled = isEnabled
    }

    /// Adopts the value the stored row carries.
    ///
    /// - Parameter enabled: The stored preference.
    public func adopt(_ enabled: Bool) {
        isEnabled = enabled
    }

    /// Whether the screen should be held awake right now.
    ///
    /// Both halves, because either alone is wrong: the preference alone would keep the screen awake
    /// while the user reads the exercise library, and the session alone would ignore the toggle
    /// `NFR-1.9` asks for.
    ///
    /// - Parameter isActive: Whether a workout is in progress — ``ActiveSessionStore/isActive``.
    /// - Returns: `true` while both hold.
    public func keepsScreenAwake(duringSession isActive: Bool) -> Bool {
        isEnabled && isActive
    }

    /// What the preference's earlier `UserDefaults` home holds, or `nil` where it was never
    /// written.
    ///
    /// This preference lived under a defaults key while the settings row had no column for it. The
    /// key is read once and cleared, so a lifter who turned the screen-wake off before the column
    /// existed does not find it back on.
    ///
    /// - Parameter defaults: Where to look. The standard suite in the app.
    /// - Returns: The stored choice, or `nil` if there is none to adopt.
    public static func legacyStoredValue(in defaults: UserDefaults = .standard) -> Bool? {
        defaults.object(forKey: legacyKey) as? Bool
    }

    /// Forgets the legacy key, so the adoption happens exactly once.
    ///
    /// - Parameter defaults: Where the key lives.
    public static func clearLegacyStoredValue(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: legacyKey)
    }

    /// The retired defaults key.
    static let legacyKey = "logging.screen-wake.enabled"
}
