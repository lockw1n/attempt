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
    /// What becomes of the load's selection when the keyboard moves.
    ///
    /// **Three answers rather than two, because letting go is not the same as selecting nothing.**
    /// A field handed no selection places its own caret; a field handed `nil` where the lifter had
    /// just aimed one loses that aim. So the rule has to be able to say *leave it alone*.
    enum SelectionChange: Equatable {
        /// Offer the whole of what the field says — the sheet has just opened over it.
        case selectAll
        /// Let go of what is held: the indices it names are about to stop meaning anything.
        case clear
        /// Leave the caret where the field put it.
        case leave
    }

    /// What the load's selection becomes as the keyboard arrives at the field or leaves it.
    ///
    /// **A field regains focus every time it is tapped, and only the first of those is an open.**
    /// Selecting the whole load on each one would take the caret away from a lifter who had aimed
    /// it between two digits, which is the correction the field exists for.
    ///
    /// **Losing the keyboard clears rather than leaves, and that is what makes the sentence above
    /// true rather than hopeful.** A range held across a blur is a range the next tap could see
    /// re-applied over the caret it had just placed — and a selection is a pair of indices into the
    /// value that was there when it was taken, which nothing guarantees is still the value.
    ///
    /// - Parameters:
    ///   - isFocused: Whether the field holds the keyboard now.
    ///   - hasOpened: Whether it has held it once already.
    /// - Returns: What to do with the selection.
    static func onFocusChange(isFocused: Bool, hasOpened: Bool) -> SelectionChange {
        guard isFocused else { return .clear }
        return hasOpened ? .leave : .selectAll
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
