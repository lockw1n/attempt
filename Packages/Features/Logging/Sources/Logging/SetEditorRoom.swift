/// How much room the Log sheet has, and the two things it gives up when it has less
/// (`FR-18.6.9`, `FR-18.6.1`, `FR-17.1.6`).
///
/// **One value rather than an `isAccessibilitySize` read in each view that reacts to it.** Two
/// things move together at that size — the skip stops being pinned, and the load stops taking the
/// keyboard as the sheet opens — and they have to: what the first gives back is what the second
/// stops spending. Written as two environment reads in two files they would be two rules, and a
/// reference picturing one of them would be a picture of a sheet nobody ships.
///
/// **Off the views, because neither consequence is readable from a hosted test.** Nothing in a test
/// bundle sees UIKit focus, and `ImageRenderer` lays a `ScrollView`'s content out and draws none of
/// it. So the switch is asserted here and its consequences through the heights they move.
enum SetEditorRoom: Equatable {
    /// Every command pinned beneath the fields, and the load holding the keyboard from the moment
    /// the sheet opens.
    case forEverything

    /// Room for what `FR-17.1.6` names and no more: **Skip this exercise** scrolls at the foot of
    /// the form and the sheet opens with the keyboard down, so Weight and Reps are both on screen.
    case forWeightAndReps

    /// Which of the two a sheet has.
    ///
    /// **`isAccessibilitySize` rather than a literal size**, because `accessibility1`–`5` all take
    /// this layout; the figures behind it were struck at `accessibility3`.
    ///
    /// **A checklist row's sheet only** (`OUT-18.6`). A free workout's form has one section and
    /// draws no skip: 476 pt of head against a row's 540, and 221 pt of pinned commands against
    /// 353 — 697 pt in all, inside the budget already. It is not short of the room this trades
    /// away, so it pays nothing for it.
    ///
    /// - Parameters:
    ///   - isRow: Whether this is a checklist row's sheet.
    ///   - isAccessibilitySize: Whether the reader has chosen an accessibility type size.
    /// - Returns: The layout that sheet takes.
    static func at(isRow: Bool, isAccessibilitySize: Bool) -> Self {
        isRow && isAccessibilitySize ? .forWeightAndReps : .forEverything
    }

    /// Whether **Skip this exercise** is pinned beneath the fields rather than scrolling with them.
    var pinsTheSkip: Bool { self == .forEverything }

    /// Whether the load takes the keyboard as the sheet opens (`FR-18.6.1`).
    ///
    /// **A separate question from ``pinsTheSkip`` though they answer together.** The skip moving is
    /// what buys the 132 pt; the keyboard waiting is what makes the room bought actually hold both
    /// fields, since the pad costs ≈306 pt more than the budget has. One of them alone leaves
    /// `FR-17.1.6` false at this size.
    var takesTheKeyboardOnOpen: Bool { self == .forEverything }
}
