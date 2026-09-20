import DesignSystem
import DesignTokens
import Localization
import SwiftUI

/// Which destructive command a host's overflow menu carries (`FR-18.4.5`).
///
/// **The write is one write and the promise is two.** Both cases call the same soft delete of the
/// session (`FR-1.2.12`, `G-1.3`); what differs is what is left afterwards, and therefore what the
/// lifter has to be told. A planned day keeps its plan on the week, so the honest word is *reset*;
/// a free workout is the only record of itself, so the honest word is *discard*.
///
/// **A case rather than a label the host passes**, so that a host cannot pass a word and forget its
/// confirmation: what a screen chooses here is the command, and the copy comes with it.
enum SessionDestructiveCommand: Hashable, Sendable {
    /// A planned day: the plan stays and the day's answers go (`FR-18.4.5`).
    case resetDay

    /// A free workout: the workout itself goes (`FR-1.2.12`, `OUT-18.6`).
    case discardWorkout

    /// What the menu item reads.
    var label: LocalizedStringResource {
        switch self {
        case .resetDay: LoggingStrings.dayResetAction
        case .discardWorkout: LoggingStrings.sessionDiscardAction
        }
    }
}

/// One command in a workout's overflow menu, in the order the menu reads them (`FR-17.9.7`).
enum SessionMenuItem: Hashable, Sendable {
    /// `FR-1.2.1`'s backdating.
    case changeDate

    /// `FR-18.4.4`'s **Skip remaining**, on the day that has rows left to answer.
    case skipRemaining

    /// The destructive one, always last.
    case destructive(SessionDestructiveCommand)
}

/// What a host's overflow menu holds, given what its workout is in (`FR-17.9.7`, `FR-18.4.4`).
///
/// **A value rather than a chain of `if`s inside the `Menu`**, because the whole of `FR-18.4.4` is
/// *which item is there in which state* — a claim a content snapshot cannot picture (a menu is not
/// in one) and a hosted walk can only reach by presenting a popover. Assertable here without
/// rendering anything, which is ``DayProgress``' rule.
///
/// **An absent item rather than a disabled one**: a disabled row in a menu is a thing the lifter
/// then has to be told the reason for, and there is no room in a menu to tell them.
struct SessionMenuContents: Equatable, Sendable {
    /// The workout's training day, or `nil` where there is no workout.
    ///
    /// **Carried here rather than passed beside this**, because it is what decides two of the
    /// three items *and* what seeds the date picker — two readings of one fact, which had drifted
    /// apart as two arguments.
    let date: Date?

    /// The commands, in order. Empty where the menu itself is not drawn.
    let items: [SessionMenuItem]

    /// Works out which commands apply.
    ///
    /// **Two different gates, and they are not the same fact.** **Change date** and the destructive
    /// command both act on a workout, so a day nobody has logged into offers neither — a menu that
    /// did would create the workout from the toolbar. **Skip remaining** answers rows rather than a
    /// workout, and on a day never started it *is* the first answer
    /// (``DayStore/skipRemaining()``), so it is offered there and the menu is drawn for it alone.
    /// That is what keeps `FR-18.4.4` a move off the foot rather than a state quietly dropped: the
    /// retiring foot was drawn on an unstarted day.
    ///
    /// - Parameters:
    ///   - date: The workout's training day, or `nil` where there is no workout.
    ///   - offersSkipRemaining: Whether a row is still unanswered. Always `false` on a host that
    ///     has no such command at all, which is the free workout (`OUT-18.6`).
    ///   - destructive: Which way back this host offers.
    init(
        date: Date?,
        offersSkipRemaining: Bool,
        destructive: SessionDestructiveCommand
    ) {
        self.date = date
        var items: [SessionMenuItem] = []
        if date != nil { items.append(.changeDate) }
        if offersSkipRemaining { items.append(.skipRemaining) }
        if date != nil { items.append(.destructive(destructive)) }
        self.items = items
    }
}

/// The things that are true of a workout rather than of a set — its training day, taking the rest
/// of a day back, and taking the workout back (`FR-17.9.7`, `FR-1.2.1`, `FR-18.4.4`, `FR-18.4.5`).
///
/// **One menu on two screens.** A day's checklist and the free workout are two hosts for the same
/// set: `FR-17.8.7` took the date picker off Train's root, so the free workout lost the only place
/// it could be backdated from, and a Discard button standing alone on the session screen was the
/// only destructive control in the app not behind a menu. What the two hosts no longer share is
/// the wording of the last item and whether the middle one is there at all — see
/// ``SessionMenuContents``.
///
/// **Named for the menu rather than for any item in it** (`G-4.2`, `NFR-1.10`): a button announcing
/// itself as **Discard** would be lying to VoiceOver about the half of it that changes a date.
struct SessionOverflowMenu: View {
    /// Which commands are drawn, in order.
    let contents: SessionMenuContents

    /// Opens the date sheet (`FR-1.2.1`).
    let changeDate: () -> Void

    /// Asks whether to answer the rest of the day Skipped (`FR-18.4.4`). The confirmation is the
    /// host's, as the destructive one's is.
    let skipRemaining: () -> Void

    /// Asks whether to take the workout back (`FR-1.2.12`). The confirmation is the host's.
    let discard: () -> Void

    var body: some View {
        Menu {
            ForEach(contents.items, id: \.self) { item in
                switch item {
                case .changeDate:
                    Button(action: changeDate) { Text(LoggingStrings.dayChangeDateAction) }
                case .skipRemaining:
                    Button(action: skipRemaining) {
                        Text(LoggingStrings.daySkipRemainingAction)
                    }
                case .destructive(let command):
                    Button(role: .destructive, action: discard) { Text(command.label) }
                }
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
    ///   - contents: Which commands the menu holds, and whether it is drawn at all. **Worked out
    ///     by the host, in a function a test can call** — ``DayView/menuContents(date:progress:)``
    ///     and ``ActiveSessionView/menuContents(date:)`` — because nothing here can read a menu
    ///     back. Measured on iOS 26.5: a toolbar's `UIMenu` holds one `UIDeferredMenuElement`
    ///     until the menu has been opened, its button declines `accessibilityActivate()`, and a
    ///     presented menu's commands belong to another window. So which host offers which command
    ///     is a claim that has to be made somewhere assertable, and this is the seam.
    ///   - side: Which corner the `⋯` sits in. **Required, with no default** (`T-16.17`), because
    ///     the two hosts now disagree: a planned day's menu moved leading to leave the trailing
    ///     corner to Done (`FR-18.4.2`), and the free workout keeps its toolbar exactly
    ///     (`OUT-18.6`). A default here would move one of them silently.
    ///   - changeDate: Moves the workout to another training day.
    ///   - skipRemaining: Answers the rest of the day Skipped (`FR-18.4.4`). **Required, with no
    ///     default and not optional**, on `side:`'s rule one line up: an optional handler beside a
    ///     `contents` that decides whether the item is drawn is the same fact in two places, and
    ///     the way they disagree is a menu row that does nothing when it is pressed. A host whose
    ///     menu never holds the command says so in its `contents` and passes a handler that says
    ///     so too — see ``ActiveSessionView/skipRemainingIsNotOffered()``.
    ///   - discard: Asks whether to take the workout back. The confirmation is the host's,
    ///     `FR-1.2.12` wanting one and a store being unable to ask.
    /// - Returns: The screen, with the menu and the sheet.
    func sessionOverflow(
        contents: SessionMenuContents,
        side: SessionToolbarSide,
        changeDate: @escaping (Date) -> Void,
        skipRemaining: @escaping () -> Void,
        discard: @escaping () -> Void
    ) -> some View {
        modifier(
            SessionOverflowModifier(
                contents: contents,
                side: side,
                changeDate: changeDate,
                skipRemaining: skipRemaining,
                discard: discard))
    }
}

/// See `sessionOverflow(contents:side:changeDate:skipRemaining:discard:)`.
struct SessionOverflowModifier: ViewModifier {
    /// Which commands the menu holds, and the day its picker opens on.
    let contents: SessionMenuContents

    /// Which corner the `⋯` sits in.
    let side: SessionToolbarSide

    /// Moves the workout to another training day.
    let changeDate: (Date) -> Void

    /// Answers the rest of the day Skipped. Required even where the item is never drawn — see
    /// `sessionOverflow(contents:side:changeDate:skipRemaining:discard:)`.
    let skipRemaining: () -> Void

    /// Asks whether to take it back.
    let discard: () -> Void

    /// Whether the date sheet is open.
    @State private var isChangingDate = false

    /// The day its picker is on. Seeded when the sheet opens, so a cancel changes nothing and no
    /// write is issued per scroll tick.
    @State private var chosenDate = Date.now

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: side.placement) {
                    if !contents.items.isEmpty {
                        SessionOverflowMenu(
                            contents: contents,
                            changeDate: {
                                guard let date = contents.date else { return }
                                chosenDate = date
                                isChangingDate = true
                            },
                            skipRemaining: skipRemaining,
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
