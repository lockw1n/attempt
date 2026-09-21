import SwiftUI

/// When the Log sheet's load takes the keyboard, and what it offers when it does (`FR-18.6.1`).
///
/// **Off the view, because neither half of this is readable from a test that renders one.** Nothing
/// in a test bundle sees UIKit focus, and a hosted accessibility tree answers whether a control
/// exists rather than what it holds — twice measured, on a toolbar and on a row's menu. So the two
/// rules the screen applies live here, where a test can call them, and what is left in the view is
/// the assignment. The simulator is still the instrument for *whether focus takes*; this is the
/// instrument for *what it does when it does*.
enum SetEditorFocus {
    /// Whether the load's field taking the keyboard is the sheet opening rather than a later tap.
    ///
    /// **A field regains focus every time it is tapped, and only the first of those is an open.**
    /// Selecting the whole load on each one would take the caret away from a lifter who had aimed
    /// it between two digits, which is the correction the field exists for.
    ///
    /// - Parameters:
    ///   - isFocused: Whether the field holds the keyboard now.
    ///   - hasOpened: Whether it has held it once already.
    /// - Returns: Whether this is the open.
    static func isOpening(isFocused: Bool, hasOpened: Bool) -> Bool {
        isFocused && !hasOpened
    }

    /// What the load's field has selected when the sheet opens over it.
    ///
    /// **The whole value, because it is a suggestion rather than something the lifter typed.** The
    /// form opens prefilled from the plan (`FR-17.1.1`), so a caret parked at one end makes `575`
    /// out of the first digit typed over `57` — which is worse than opening with nothing focused.
    ///
    /// **An empty field selects nothing rather than an empty range.** A plan may name repetitions
    /// and no load (`FR-15.2.2`); there is nothing to replace, and `nil` leaves the field to place
    /// its own insertion point, which is the same place an empty range names.
    ///
    /// - Parameter text: What the field already says.
    /// - Returns: The whole of it, or `nil` where there is nothing to select.
    static func selectionOnOpen(of text: String) -> TextSelection? {
        guard !text.isEmpty else { return nil }
        return TextSelection(range: text.startIndex..<text.endIndex)
    }
}
