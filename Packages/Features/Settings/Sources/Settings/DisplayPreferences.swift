import DesignSystem
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// How the app draws right now: the theme (`FR-1.10.2`) and the step weights read to (`G-3.3`) —
/// one for the whole app.
///
/// **A store rather than a screen's state** (`TR-1.2`): a preference picked in Settings has to
/// reach every screen already on a stack, including the three tabs the user is not looking at. The
/// app target seeds it at launch and tells it again on every write, the same shape `NFR-1.9`'s
/// preference has.
@Observable
public final class DisplayPreferences {
    /// What the stored row says, or `nil` while it has not been read.
    ///
    /// The two are different: an unread row is `G-7.1`'s dark, and a row saying
    /// ``RepositoryInterface/ThemePreference/system`` is the device's choice.
    public private(set) var theme: ThemePreference?

    /// The step weights read to, or `nil` where the display unit's factory step stands (`G-3.3`).
    public private(set) var weightPrecision: DisplayPrecision?

    /// Starts unread.
    ///
    /// - Parameters:
    ///   - theme: The stored theme, or `nil` while the row has not been read.
    ///   - weightPrecision: The stored step, or `nil` for the unit's own.
    public init(theme: ThemePreference? = nil, weightPrecision: DisplayPrecision? = nil) {
        self.theme = theme
        self.weightPrecision = weightPrecision
    }

    /// Adopts what the stored row carries.
    ///
    /// - Parameter settings: The row as it now stands.
    public func adopt(_ settings: UserSettings) {
        theme = settings.theme
        weightPrecision = settings.displayPrecision
    }

    /// What `preferredColorScheme` is given: the user's choice, `nil` where they asked to follow
    /// the device, and `G-7.1`'s dark until the row has been read.
    public var colorScheme: ColorScheme? {
        guard let theme else { return Appearance.defaultColorScheme }
        return theme.colorScheme
    }
}

extension ThemePreference {
    /// This preference as SwiftUI's, `nil` meaning "whatever the device is set to".
    ///
    /// **`system` is `nil` and not `G-7.1`'s dark**, which is the whole difference between a
    /// preference expressed and one never made: a first launch gets dark from
    /// ``SettingsRepository/settings()``'s own first-launch choice, and a lifter who then picks
    /// *System* is asking for something else.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
