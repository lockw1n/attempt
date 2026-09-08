import DesignSystem
import DesignTokens
import Localization
import SwiftUI

/// The two things that are true of a workout rather than of a set — its training day and throwing
/// it away (`FR-17.9.7`, `FR-1.2.1`, `FR-1.2.12`).
///
/// **One menu on two screens.** A day's checklist and the free workout are two hosts for the same
/// pair: `FR-17.8.7` took the date picker off Train's root, so the free workout lost the only place
/// it could be backdated from, and a Discard button standing alone on the session screen was the
/// only destructive control in the app not behind a menu.
///
/// **Named for the menu rather than for either item** (`G-4.2`, `NFR-1.10`): a button announcing
/// itself as **Discard** would be lying to VoiceOver about the half of it that changes a date.
struct SessionOverflowMenu: View {
    /// Opens the date sheet (`FR-1.2.1`).
    let changeDate: () -> Void

    /// Asks whether to throw the workout away (`FR-1.2.12`). The confirmation is the host's.
    let discard: () -> Void

    var body: some View {
        Menu {
            Button(action: changeDate) { Text(LoggingStrings.dayChangeDateAction) }
            Button(role: .destructive, action: discard) {
                Text(LoggingStrings.sessionDiscardAction)
            }
        } label: {
            Label(String(localized: LoggingStrings.dayMenuAction), systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
    }
}

/// `FR-1.2.1`'s backdating, as a sheet over whichever screen opened it.
///
/// **The picker writes nothing until Done.** A `DatePicker` bound straight to the store would issue
/// a write per scroll tick, each one restamping `updatedAt` — `G-2.4`'s conflict key — for a date
/// the lifter passed through on the way to the one they meant.
struct WorkoutDateSheet: View {
    /// The day being chosen. The host's state, so a cancel is the sheet closing.
    @Binding var day: Date

    /// Applies it and closes.
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            WorkoutDateSection(day: $day)
            Button(action: done) {
                Text(LoggingStrings.dayChangeDateDone)
            }
            .buttonStyle(.primaryAction(.fill))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg.points)
        .background(ColorToken.background)
    }
}

extension View {
    /// `FR-17.9.7`'s menu and the sheet it opens, attached to whichever screen owns the workout.
    ///
    /// **A modifier rather than two blocks on each host**, because the day's checklist and the free
    /// workout would otherwise carry the same toolbar item, the same sheet and the same pair of
    /// `@State`s twice — which is two places for the picker to start writing per scroll tick.
    ///
    /// - Parameters:
    ///   - date: The workout's training day, or `nil` where there is no workout — which is also
    ///     what hides the menu. A day nobody has logged into has no date to change and nothing to
    ///     discard, and a menu offering both would create the workout from the toolbar.
    ///   - changeDate: Moves the workout to another training day.
    ///   - discard: Asks whether to throw it away. The confirmation is the host's, `FR-1.2.12`
    ///     wanting one and a store being unable to ask.
    /// - Returns: The screen, with both.
    func sessionOverflow(
        date: Date?,
        changeDate: @escaping (Date) -> Void,
        discard: @escaping () -> Void
    ) -> some View {
        modifier(SessionOverflowModifier(date: date, changeDate: changeDate, discard: discard))
    }
}

/// See ``SwiftUI/View/sessionOverflow(date:changeDate:discard:)``.
struct SessionOverflowModifier: ViewModifier {
    /// The workout's training day, or `nil` where there is no workout.
    let date: Date?

    /// Moves the workout to another training day.
    let changeDate: (Date) -> Void

    /// Asks whether to throw it away.
    let discard: () -> Void

    /// Whether the date sheet is open.
    @State private var isChangingDate = false

    /// The day its picker is on. Seeded when the sheet opens, so a cancel changes nothing and no
    /// write is issued per scroll tick.
    @State private var chosenDate = Date.now

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if let date {
                        SessionOverflowMenu(
                            changeDate: {
                                chosenDate = date
                                isChangingDate = true
                            },
                            discard: discard)
                    }
                }
            }
            .sheet(isPresented: $isChangingDate) {
                WorkoutDateSheet(day: $chosenDate) {
                    isChangingDate = false
                    changeDate(chosenDate)
                }
                .presentationDetents([.medium])
            }
    }
}
