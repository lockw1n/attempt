import SwiftUI

/// App-wide appearance defaults (`G-7.1`).
public enum Appearance {
    /// The scheme the app adopts before the user has expressed a preference: dark.
    ///
    /// `G-7.1` makes dark the design's primary target and light its secondary one, and this is the
    /// single place that says so in code. The user's own choice (`FR-1.10.2`) overrides it; nothing
    /// here reads or stores that setting.
    public static let defaultColorScheme: ColorScheme = .dark
}
