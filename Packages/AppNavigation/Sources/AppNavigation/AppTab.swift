/// The four tabs (`D-8`): Home, Train, History, Settings.
///
/// `allCases` is the tab bar's order, left to right — the tab bar reads it rather than listing the
/// cases again, so this declaration is the only place the order is stated.
///
/// **The raw values are persisted** (they are half of a restored ``NavigationSnapshot``), so
/// renaming a case is a migration and not a rename. Adding a fifth case is a `D-8` decision, not a
/// code change: Q-1.2 resolved the tab set for the whole of Phase 1, and a setting that does not
/// fit one of these four names has the wrong name.
public enum AppTab: String, Hashable, Sendable, Codable, CaseIterable, Identifiable {
    /// The dashboard (`FR-1.9`) — e1RM tiles, last workout, the "Start workout" action.
    case home

    /// Workout logging (`FR-1.2`), the exercise library (`FR-1.1`) and the plate calculator
    /// (`FR-1.4`), per Q-1.2's split.
    case train

    /// Past sessions, per-exercise history, the calendar and search (`FR-1.5`).
    case history

    /// Preferences (`FR-1.10`), data portability (`FR-1.11`) and sync (`FR-1.12`).
    case settings

    /// `Identifiable` conformance, so the tab bar can be built by enumerating `allCases`.
    public var id: String { rawValue }

    /// The SF Symbol the tab bar draws.
    ///
    /// A name, not a styled image: the symbol takes the tab bar's own treatment, which is what
    /// keeps a tab icon from acquiring a size or a colour this app would then have to maintain
    /// against two appearances. It is also why there is no `DesignSystem` token behind it: an
    /// unstyled name is the whole of the treatment, so a token would have nothing left to carry.
    public var symbolName: String {
        switch self {
        case .home: "square.grid.2x2"
        case .train: "figure.strengthtraining.traditional"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}
