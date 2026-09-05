import Foundation
import SwiftUI

/// Where a resumed workout opens (`FR-16.6.1`).
///
/// **A value with one rule in it, so the rule can be asserted without a rendering.** What the screen
/// does with the answer — scroll to it, once — is the screen's; which card that is, is a fact about
/// the workout, and it is the half that has cases worth pinning.
enum SessionResumeTarget {
    /// The card a resumed session should scroll to, or `nil` where it should not scroll at all.
    ///
    /// **The first exercise ``SessionExercise/isDone`` is false for**, which is a set count *or*
    /// `FR-15.3.4`'s check, whichever arrives — not the set count alone. An exercise a lifter
    /// skipped or finished early is done whatever its rows say, and reading only the sets would
    /// send a resumed session back to work its owner has already dismissed.
    ///
    /// **`nil` when that exercise is the first one**, and this is the case that keeps the answer
    /// honest rather than merely tidy: the screen already opens on the first card, so scrolling to
    /// it would push the workout's own line off the top to reach something that was in view — a
    /// jump with nothing gained, on the ordinary path where a lifter has done nothing yet.
    ///
    /// **`nil` when every exercise is done**, too. There is no exercise in progress to return to,
    /// and the thing that is wanted then is **Finish** — which is the foot of the screen, not a
    /// card, and scrolling there is a bigger claim than `FR-16.6.1` makes.
    ///
    /// - Parameter exercises: The workout's exercises, in order.
    /// - Returns: The entry to scroll to, or `nil`.
    static func exerciseInProgress(in exercises: [SessionExercise]) -> UUID? {
        guard let index = exercises.firstIndex(where: { !$0.isDone }), index > 0 else { return nil }
        return exercises[index].id
    }
}

extension View {
    /// The navigation title drawn inline rather than large (`NFR-16.3`).
    ///
    /// **Conditional because the modifier is**, and this package compiles for macOS as well: the
    /// tests run there under `swift test`, and `navigationBarTitleDisplayMode` is unavailable
    /// outside iOS. macOS has no large-title block to collapse, so doing nothing there is the same
    /// layout rather than a lesser one.
    ///
    /// - Returns: The view, with its title collapsed where a platform has one to collapse.
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
            return navigationBarTitleDisplayMode(.inline)
        #else
            return self
        #endif
    }
}
