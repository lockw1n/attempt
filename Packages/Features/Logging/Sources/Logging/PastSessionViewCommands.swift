import Foundation
import SwiftUI

/// What `history.session`'s delete question named, kept apart from whether it is being asked
/// (`FR-18.7.5`).
///
/// **The question outlives the target by one animation.** A confirmation dismissed is still on
/// screen while it animates out, and a title read off state that has already been cleared re-reads
/// as *Delete the workout on 1 January 1?* on the way down — `DayView.askedSetCount` is the worked
/// example, and this is the same rule with both of its facts in one value rather than two.
///
/// ``unasked`` names no day and no work, which is what a screen that has never asked holds.
struct PastSessionDeleteQuestion: Equatable {
    /// The session's training day, as the question named it.
    let day: Date

    /// How many logged sets it said would go — warm-ups included, on
    /// ``PastSessionState/loggedSetCount``'s rule.
    let setCount: Int

    /// Before anything has been asked.
    static let unasked = PastSessionDeleteQuestion(day: .distantPast, setCount: 0)
}

/// `history.session`'s own overflow menu — the third host of the seam (`FR-18.7.3`, `FR-18.7.4`,
/// `FR-18.7.5`).
///
/// **A file of its own**, on ``ActiveSessionView``'s commands file's argument: the screen grows as
/// a session gains content, and this grows as correcting one gains conditions.
extension PastSessionView {
    /// What this screen's `⋯` holds (`FR-18.7.3`).
    ///
    /// **Change date and Delete workout, and nothing else.** There is no plan to skip the rest of
    /// — the day has been answered (`OUT-18.10`) — and none to edit from here (`OUT-18.11`); what
    /// is left is the two corrections `F-14` asked for.
    ///
    /// **`startsWhenDated: false`**, which is the free workout's answer and for a sharper reason:
    /// this screen is addressed *by a session id*, so a date offered before there is a session
    /// would be a date on a row the route could not have named. Where the session has not been read
    /// yet, or resolved to nothing, the menu is empty and the modifier draws no `⋯` at all.
    ///
    /// **And nothing at all on a workout that has not ended** (`FR-18.7.5`: *a past session*).
    /// History lists open workouts too — `FR-16.4.3` gives them a state and `FR-16.4.4` a way out —
    /// and every row it lists links here, so this screen is reachable for the workout the Train tab
    /// is holding right now. ``ActiveSessionStore/resume()`` *keeps* a held free workout and reads
    /// nothing, so a delete made from here would leave that store publishing a session whose rows
    /// are soft-deleted, and the next set would be logged into them. A re-date has the mirror
    /// shape: the store's copy keeps the old day, and the next write rebuilt from it puts that day
    /// back. Nothing is lost by waiting — `FR-16.4.4`'s **Finish** is on the row for exactly the
    /// workout left open, and the menu is here the moment it has been used.
    ///
    /// **One answer for both drawings** (`Q-18.3` at (a)): a past planned day and a past free
    /// workout get the same two commands, because the lifter does not know which shape they are
    /// looking at and a toolbar that changed with the session's provenance would be a thing to
    /// explain. It is why the destructive command is ``SessionDestructiveCommand/deleteWorkout``
    /// on both rather than ``SessionDestructiveCommand/resetDay`` on one of them.
    ///
    /// - Parameters:
    ///   - date: The session's training day, or `nil` in every state that holds no session.
    ///   - hasEnded: Whether the workout is over (`WorkoutSession/isFinished`). **A separate fact
    ///     from there being a date**, and the population that separates them is the workout open
    ///     today: it has a training day, it is on History's list, and it is the one another screen
    ///     may be holding — see above.
    /// - Returns: The commands, in order.
    static func menuContents(date: Date?, hasEnded: Bool) -> SessionMenuContents {
        SessionMenuContents(
            date: hasEnded ? date : nil,
            startsWhenDated: false,
            offersPlanEditing: false,
            offersSkipRemaining: false,
            destructive: .deleteWorkout)
    }

    /// What those items do, beside ``menuContents(date:hasEnded:)`` which says which are drawn.
    ///
    /// **The question is raised here and the write is made in the dialog's own action**, which is
    /// `FR-1.2.12`'s shape on all three hosts: a store cannot ask, so the screen does.
    var menuCommands: SessionMenuCommands {
        SessionMenuCommands(
            editPlan: SessionMenuCommands.notOffered("Edit plan", on: "a past session"),
            skipRemaining: SessionMenuCommands.notOffered("Skip remaining", on: "a past session"),
            discard: askToDelete)
    }

    /// Raises the delete question over the session on screen (`FR-18.7.5`).
    ///
    /// A screen holding no session asks nothing: the menu that would raise it is not drawn, so
    /// reaching this without one is a wiring fault rather than a state.
    func askToDelete() {
        guard let session = state.session else { return }
        askedDelete = PastSessionDeleteQuestion(
            day: session.date, setCount: state.loggedSetCount)
        isConfirmingDelete = true
    }

    /// Deletes the session and leaves the screen (`FR-18.7.5`).
    ///
    /// **The screen closes only on a write that landed.** A refusal leaves every row where it was
    /// and reports through the banner the other corrections use, so the retry is another tap at the
    /// same command rather than a workout the lifter has to find again — which is
    /// ``ActiveSessionView/discard()``'s rule, taken over a screen that can be popped.
    ///
    /// **``SessionExit/leave(_:)`` rather than `dismiss()`**, for that method's measured reason: a
    /// screen with a sheet of its own up is not the topmost thing on the display. The fallback is
    /// what a preview and a hosted fixture get.
    ///
    /// **What it closes *onto* re-reads for itself.** Nothing in this app is told about a write it
    /// did not make, so History's three screens show the deleted session gone because each one
    /// reads again when it appears — see `DOD-18.9`.
    func deleteWorkout() async {
        guard await state.delete() else { return }
        if !SessionExit.leave(navigation) { dismiss() }
    }
}
