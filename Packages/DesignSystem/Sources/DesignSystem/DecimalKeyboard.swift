import SwiftUI

extension View {
    /// The decimal keyboard, where the platform has one.
    ///
    /// **A modifier rather than an `#if` at every call site.** `keyboardType(_:)` does not exist on
    /// macOS, and these packages build for both — each manifest's `platforms:` clause names them.
    ///
    /// Here rather than in the module that first needed it: a second module now enters a weight
    /// (`FR-1.7.5`), and a numeric field is a component-layer concern.
    ///
    /// **This modifier is why `G-3.4`'s silent refusal is not a defect on a phone, and that is a
    /// decision rather than an accident.** `LocalizedNumberField` refuses a string that is not, in
    /// whole, a number in the user's locale and says nothing when it does; `.decimalPad` offers no
    /// `.` key in a comma-decimal locale, so the refusing input cannot be typed from the keyboard
    /// this app ships. A hardware keyboard can still reach it — iPad, Mac, a paired Bluetooth one —
    /// and T-1.92 recorded the answer that no message is owed there.
    ///
    /// **The premise is what decays, so it is a gate**: `scripts/check-decimal-keyboard.sh` holds
    /// the host inventory as an exact set and refuses any source that sets `keyboardType` by hand.
    /// A host added without it reopens the decision rather than inheriting it.
    public func decimalKeyboard() -> some View {
        #if os(iOS)
            return keyboardType(.decimalPad)
        #else
            return self
        #endif
    }
}
