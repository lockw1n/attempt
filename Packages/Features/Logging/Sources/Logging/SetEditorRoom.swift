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
    /// **A checklist row's sheet only, because that is the sheet the claim is made about**
    /// (`OUT-18.6`). `FR-18.6.9` is `FR-17.1.6`'s, and `FR-17.1.6` is the Log sheet a checklist row
    /// opens; a free workout's form has one section, draws no skip, and has never been measured at
    /// an accessibility size with the pad up. It is **not** asserted to fit there — it keeps the
    /// focus, so it opens with the ≈306 pt pad, and 306 against what a `.large` sheet gets leaves
    /// less than the head alone needs, exactly as it does for a row. What it does not have is a
    /// skip to move, so the trade this makes is not available to it either: the layout is withheld
    /// because it would buy nothing, not because the sheet is comfortable.
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
