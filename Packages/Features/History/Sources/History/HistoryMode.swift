import DesignSystem
import Foundation
import SwiftUI

/// Which of the History tab's two readings of the same rows is on screen (`FR-17.11.1`).
///
/// **A mode of `tab.history` rather than a tab of its own**, which is `D-8`'s four tabs holding: the
/// chronological log and the week view read the same sessions and answer two questions about them —
/// *what did I do* and *what did a week look like*. Neither is a filter on the other, and neither is
/// a place the app is restored to, so the choice is a control on one screen.
enum HistoryMode: String, CaseIterable, Identifiable, Sendable {
    /// `FR-1.5.1`'s chronological log, cut into months (`FR-16.6.3`).
    case sessions

    /// `FR-17.11`'s calendar weeks.
    case weeks

    /// The case's own name — stable, and never persisted anywhere.
    var id: String { rawValue }
}

/// Which mode the History tab was last left in, for as long as the app is running.
///
/// **Process-lifetime state and deliberately not a settings column** (`T-16.14`): a column nothing
/// else reads is a column the archive owes a field and a restore owes a mapping, for a convenience
/// whose whole value is that the tab is where the user left it this session. ``ExerciseListFilterMemory``
/// is the same shape one module along, and its own note on `nil` is why this one has a default
/// instead: there is no "neither mode", so the first launch has an answer rather than an absence.
@MainActor
final class HistoryModeMemory {
    /// The app's one memory. A test builds its own instead.
    static let shared = HistoryModeMemory()

    /// The mode the tab opens in — the log until something says otherwise.
    private(set) var mode: HistoryMode = .sessions

    /// Builds a memory holding the default.
    init() {}

    /// Records a choice.
    ///
    /// - Parameter mode: What the control is now set to.
    func remember(_ mode: HistoryMode) {
        self.mode = mode
    }
}

/// `FR-17.11.1`'s two readings of the same rows, as one control above them.
///
/// **A segmented picker rather than a toolbar item**, which is where the calendar's own way in sits:
/// the calendar is a different screen and this is the same one twice, so the control that switches
/// between them belongs in the content rather than in the chrome.
///
/// The label names the *choice* rather than either option (`G-4.2`): the segments announce
/// themselves, and a screen reader needs to know what they are segments of.
///
/// A view of its own rather than a `@ViewBuilder` on ``SessionListView``, on this module's usual
/// rule: a reference must not need the repositories that screen builds its state over.
struct HistoryModeControl: View {
    /// Which mode is showing.
    @Binding var mode: HistoryMode

    /// The two segments.
    var body: some View {
        Picker(selection: $mode) {
            Text(HistoryStrings.modeSessions).tag(HistoryMode.sessions)
            Text(HistoryStrings.modeWeeks).tag(HistoryMode.weeks)
        } label: {
            Text(HistoryStrings.modeLabel)
        }
        .pickerStyle(.segmented)
    }
}
