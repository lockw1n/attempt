import Foundation
import PowerliftingCore

/// What the preference pickers offer, as values rather than as views (`FR-1.10.1`, `G-3.3`,
/// `FR-1.7.1`).
///
/// **Every list includes the value in force**, even one this app would never have offered — a
/// stored row can carry an increment from another unit, a restore, or a later version. A picker
/// whose selection is absent from its own options draws no selection at all, and the user's next
/// tap would then silently replace a setting they came to read.
enum SettingsOptions {
    /// The display steps offered, finest first (`G-3.3`). `nil` is not among them: "follow the
    /// unit" is the picker's own case, because it is the absence of a choice rather than a step.
    ///
    /// - Parameter current: The step in force, or `nil` where the unit decides.
    /// - Returns: The steps to offer, ascending.
    static func displayPrecisions(including current: DisplayPrecision?) -> [DisplayPrecision] {
        let offered: [DisplayPrecision] = [.tenth, .quarter, .half, .whole]
        guard let current, !offered.contains(current) else { return offered }
        return (offered + [current]).sorted { $0.milliUnits < $1.milliUnits }
    }

    /// The loadable increments offered for `unit` (`FR-1.5.1.6`).
    ///
    /// **Unit-dependent, and the stored value is grams either way** (`G-1.1`). A gym's plates come
    /// in the unit its lifters count in, so a pound list of kilogram steps would offer nobody a
    /// step they own — 2.5 kg is 5.51 lb.
    ///
    /// - Parameters:
    ///   - unit: The unit the user is reading in.
    ///   - current: The increment in force.
    /// - Returns: The increments to offer, ascending.
    static func roundingIncrements(for unit: MassUnit, including current: Weight) -> [Weight] {
        let offered =
            switch unit {
            case .kilograms: [500, 1_000, 1_250, 2_500, 5_000].map(Weight.init(grams:))
            case .pounds:
                [1.0, 2.5, 5.0, 10.0].compactMap { Weight(pounds: $0, rounding: .nearest) }
            }
        guard !offered.contains(current) else { return offered }
        return (offered + [current]).sorted()
    }

    /// The lookback windows offered, in days (`FR-1.7.1`).
    ///
    /// - Parameter current: The window in force.
    /// - Returns: The windows to offer, ascending.
    static func lookbackWindows(including current: Int) -> [Int] {
        let offered = [30, 60, 90, 180, 365]
        guard !offered.contains(current) else { return offered }
        return (offered + [current]).sorted()
    }
}
