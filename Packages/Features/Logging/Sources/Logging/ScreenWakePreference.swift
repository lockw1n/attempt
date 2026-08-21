import Foundation

/// Whether the screen is held awake while a workout is being logged (`NFR-1.9`).
///
/// **The decision is here and the mechanism is not.** Turning the idle timer off is `UIApplication`'s
/// and belongs to the app target; what this owns is the one boolean the user controls and the rule
/// that combines it with whether a workout is in progress — which is the half worth a test.
///
/// **Its storage is a stub, deliberately, and `UserDefaults` rather than the settings row.**
/// `FR-1.10`'s preferences live on ``RepositoryInterface/UserSettings``, which has no column for
/// this one: schema v1 is frozen and adding a column is a migration, not a screen's business. The
/// real row is T-1.60's, and it takes this key's value with it — until then a preference the user
/// set has to survive a relaunch, which an in-memory flag would not.
@Observable
public final class ScreenWakePreference {
    /// Whether the user wants the screen kept awake during a workout.
    ///
    /// **Defaults to on**, which is what `NFR-1.9` describes: the requirement is that the screen
    /// stays awake and the toggle is the way out of it, not the way into it. A lifter's hands are
    /// chalked and the phone is on the floor between sets.
    public private(set) var isEnabled: Bool

    @ObservationIgnored private let defaults: UserDefaults

    /// Reads the stored preference, or the default where nothing has been stored.
    ///
    /// - Parameter defaults: Where the preference is kept. The standard suite in the app; a
    ///   throwaway suite in a test, which is what keeps one test's choice out of the next one's.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `object(forKey:)` rather than `bool(forKey:)`: the latter answers `false` for a key that
        // has never been written, which is the opposite of this preference's default.
        isEnabled = defaults.object(forKey: Self.key) as? Bool ?? true
    }

    /// Stores the user's choice.
    ///
    /// A method rather than a settable property, so the write to storage cannot be forgotten by a
    /// caller and so the `@Observable` macro has a plain stored property to work with.
    ///
    /// - Parameter enabled: What the user asked for.
    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.key)
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

    /// The defaults key. T-1.60 migrates whatever is under it into the settings row.
    static let key = "logging.screen-wake.enabled"
}
