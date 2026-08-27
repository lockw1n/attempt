import SwiftUI

extension View {
    /// The decimal keyboard, where the platform has one.
    ///
    /// **A modifier rather than an `#if` at every call site.** `keyboardType(_:)` does not exist on
    /// macOS, and these packages build for both — each manifest's `platforms:` clause names them.
    ///
    /// Here rather than in the module that first needed it: a second module now enters a weight
    /// (`FR-1.7.5`), and a numeric field is a component-layer concern.
    public func decimalKeyboard() -> some View {
        #if os(iOS)
            return keyboardType(.decimalPad)
        #else
            return self
        #endif
    }
}
