import PowerliftingCore
import SwiftUI

extension EnvironmentValues {
    /// The step displayed weights read to (`G-3.3`), or `nil` where the display unit's own factory
    /// step stands.
    ///
    /// **Ambient rather than threaded, for `locale`'s reason.** Precision is a property of how the
    /// app renders rather than of any one screen's data, and every screen that draws a load would
    /// otherwise carry a parameter through each view between the settings read and the number —
    /// measured at eight call sites across four feature modules when this landed.
    ///
    /// The default is `nil` and not a step: a view rendered outside the app — a preview, a
    /// snapshot — must draw what a lifter who never configured one sees, which depends on the unit
    /// and so cannot be a constant here.
    @Entry public var displayPrecision: DisplayPrecision?
}
