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

    /// A session that is over, reached from History: the workout itself goes, and there is nothing
    /// to come back to (`FR-18.7.5`).
    ///
    /// **It is this on a past *planned* day as well, never ``resetDay``.** A day of a week already
    /// over has no *upcoming* for the plan to be returned to, so the promise that word makes on the
    /// checklist is one this screen cannot keep.
    case deleteWorkout

    /// What the menu item reads.
    var label: LocalizedStringResource {
        switch self {
        case .resetDay: LoggingStrings.dayResetAction
        case .discardWorkout: LoggingStrings.sessionDiscardAction
        case .deleteWorkout: LoggingStrings.pastSessionDeleteAction
        }
    }
}

/// One command in a workout's overflow menu, in the order the menu reads them (`FR-17.9.7`).
enum SessionMenuItem: Hashable, Sendable {
    /// `FR-1.2.1`'s backdating.
    case changeDate

    /// `FR-18.7.2`'s **Edit plan**, on the day no workout has been written for yet.
    case editPlan

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
    /// **Carried here rather than passed beside this**, because it is what decides three of the
    /// five items *and* what seeds the date picker — two readings of one fact, which had drifted
    /// apart as two arguments. Where it is `nil` and the picker is offered anyway
    /// (`startsWhenDated`), the sheet opens on today: the day has not happened yet, so there is no
    /// other date to open on.
    let date: Date?

    /// The commands, in order. Empty where the menu itself is not drawn.
    let items: [SessionMenuItem]

    /// Works out which commands apply.
    ///
    /// **Four gates, and no two of them are the same fact.** The destructive command acts on a
    /// workout, so a day nobody has logged into offers none. **Skip remaining** answers rows rather
    /// than a workout, and on a day never started it *is* the first answer
    /// (``DayStore/skipRemaining()``), so it is offered there too. That is what keeps `FR-18.4.4` a
    /// move off the foot rather than a state quietly dropped: the retiring foot was drawn on an
    /// unstarted day.
    ///
    /// **Change date used to be the destructive command's twin and is not one any more**
    /// (`FR-18.7.1`, `F-13`). A host that acquires its workout *by being dated* offers it with no
    /// workout held — the chosen day is what the session is created on, one write, never a create
    /// and a restamp. A host that does not stays as it was: dating a free workout that does not
    /// exist would conjure one out of a toolbar.
    ///
    /// **Edit plan is the one command that goes away once there is a workout** (`FR-18.7.2`,
    /// `Q-18.9` at (a)), and the rule is here rather than on a host so that it holds for every one
    /// of them: a started day keeps the targets it started with (`FR-17.10.5`), so an edit made
    /// then would change nothing on the screen the lifter came back to. With `startsWhenDated`
    /// that means **Change date** hides **Edit plan**, which is `Q-18.9`'s stated interaction and
    /// is what ``SessionDestructiveCommand/resetDay`` is the way back from.
    ///
    /// - Parameters:
    ///   - date: The workout's training day, or `nil` where there is no workout.
    ///   - startsWhenDated: Whether dating this screen *creates* its workout (`FR-18.7.1`), which
    ///     is what lets **Change date** be offered before there is one. The planned day answers
    ///     whether it has a routine to copy — ``DayStore/hasPlan`` — because a date it could not
    ///     act on is a menu item that does nothing.
    ///   - offersPlanEditing: Whether a week holds this day, so **Edit plan** has something to
    ///     open at (`FR-18.7.2`). **A separate fact from `startsWhenDated`**, not a second reading
    ///     of it: a day whose routine has been archived (`FR-15.2.5`) is still in the week and is
    ///     exactly the day a lifter needs the plan editor for, while nothing can be started on it.
    ///   - offersSkipRemaining: Whether a row is still unanswered. Always `false` on a host that
    ///     has no such command at all, which is the free workout (`OUT-18.6`).
    ///   - destructive: Which way back this host offers.
    init(
        date: Date?,
        startsWhenDated: Bool,
        offersPlanEditing: Bool,
        offersSkipRemaining: Bool,
        destructive: SessionDestructiveCommand
    ) {
        self.date = date
        var items: [SessionMenuItem] = []
        if date != nil || startsWhenDated { items.append(.changeDate) }
        if date == nil, offersPlanEditing { items.append(.editPlan) }
        if offersSkipRemaining { items.append(.skipRemaining) }
        if date != nil { items.append(.destructive(destructive)) }
        self.items = items
    }
}

/// What a host's overflow menu *does*, as one value beside the ``SessionMenuContents`` that says
/// what it holds.
///
/// **One value rather than four closures on the modifier**, and the reason is the same one that
/// made `skipRemaining:` required rather than optional: every handler here is paired with a rule
/// in ``SessionMenuContents`` about whether its item is drawn at all, and the two halves belong
/// where they can be read together. A host whose menu never holds a command still answers for it —
/// see ``SessionMenuCommands/notOffered(_:on:)``.
///
/// **Change date is not here.** Its item does not run a handler; it opens the sheet the modifier
/// owns, seeded from ``SessionMenuContents/date``, and what the host supplies is what to do with
/// the day that comes back.
struct SessionMenuCommands {
    /// Opens the week's plan at this day (`FR-18.7.2`). It leaves the screen, so there is nothing
    /// to confirm.
    let editPlan: () -> Void

    /// Asks whether to answer the rest of the day Skipped (`FR-18.4.4`). The confirmation is the
    /// host's, as the destructive one's is.
    let skipRemaining: () -> Void

    /// Asks whether to take the workout back (`FR-1.2.12`). The confirmation is the host's,
    /// `FR-1.2.12` wanting one and a store being unable to ask.
    let discard: () -> Void

    /// A handler for a command this host's ``SessionMenuContents`` never draws.
    ///
    /// **A handler that says so, rather than the `nil` the modifier used to take.** An optional
    /// handler beside a ``SessionMenuContents`` that decides whether its item is drawn is one fact
    /// in two places, and the way the two disagree is a menu row that does nothing when it is
    /// pressed — silent, and invisible to every test that reads the contents. So reaching one of
    /// these is a wiring fault rather than a state the app is ever in.
    ///
    /// **One factory rather than a pair of named methods per host**, now that there are three
    /// hosts (`FR-18.7.3`): what each of them *does* here is the same assertion, and the only
    /// thing that differs is which command and which screen — which is what the diagnostic
    /// carries. Six near-identical methods would have been one fact written six times.
    ///
    /// - Parameters:
    ///   - command: The item, as the menu would read it.
    ///   - host: The screen that never draws it.
    /// - Returns: The handler.
    static func notOffered(_ command: String, on host: String) -> () -> Void {
        { assertionFailure("\(host)'s menu never offers \(command)") }
    }
}

/// The things that are true of a workout rather than of a set — its training day, taking the rest
/// of a day back, and taking the workout back (`FR-17.9.7`, `FR-1.2.1`, `FR-18.4.4`, `FR-18.4.5`).
///
/// **One menu on three screens.** A day's checklist and the free workout were the first two hosts
/// for the same set: `FR-17.8.7` took the date picker off Train's root, so the free workout lost
/// the only place it could be backdated from, and a Discard button standing alone on the session
/// screen was the only destructive control in the app not behind a menu. The past session is the
/// third (`FR-18.7.3`), and draws it only once the workout has ended. What the hosts no longer
/// share is the wording of the last item and whether the middle one is there at all — see
/// ``SessionMenuContents``.
///
/// **Named for the menu rather than for any item in it** (`G-4.2`, `NFR-1.10`): a button announcing
/// itself as **Discard** would be lying to VoiceOver about the half of it that changes a date.
struct SessionOverflowMenu: View {
    /// Which commands are drawn, in order.
    let contents: SessionMenuContents

    /// Opens the date sheet (`FR-1.2.1`), on the day the host seeded.
    let changeDate: () -> Void

    /// What each of the others does.
    let commands: SessionMenuCommands

    var body: some View {
        Menu {
            ForEach(contents.items, id: \.self) { item in
                switch item {
                case .changeDate:
                    Button(action: changeDate) { Text(LoggingStrings.dayChangeDateAction) }
                case .editPlan:
                    Button(action: commands.editPlan) { Text(LoggingStrings.dayEditPlanAction) }
                case .skipRemaining:
                    Button(action: commands.skipRemaining) {
                        Text(LoggingStrings.daySkipRemainingAction)
                    }
                case .destructive(let command):
                    Button(role: .destructive, action: commands.discard) { Text(command.label) }
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
    ///     by the host, in a function a test can call** — ``DayView/menuContents(date:startsWhenDated:offersPlanEditing:progress:)``,
    ///     ``ActiveSessionView/menuContents(date:)`` and ``PastSessionView/menuContents(date:hasEnded:)``
    ///     — because nothing here can read a menu back. Measured on iOS 26.5: a toolbar's `UIMenu`
    ///     holds one `UIDeferredMenuElement`
    ///     until the menu has been opened, its button declines `accessibilityActivate()`, and a
    ///     presented menu's commands belong to another window. So which host offers which command
    ///     is a claim that has to be made somewhere assertable, and this is the seam.
    ///   - changeDate: Moves the workout to another training day — or, where the host said
    ///     `startsWhenDated`, creates it on that day (`FR-18.7.1`).
    ///   - commands: What the menu's other items do. **One value, and every handler in it is
    ///     required with no default and not optional** — an optional handler beside a `contents`
    ///     that decides whether the item is drawn is the same fact in two places, and the way they
    ///     disagree is a menu row that does nothing when it is pressed. See ``SessionMenuCommands``.
    /// - Returns: The screen, with the menu and the sheet.
    func sessionOverflow(
        contents: SessionMenuContents,
        changeDate: @escaping (Date) -> Void,
        commands: SessionMenuCommands
    ) -> some View {
        modifier(
            SessionOverflowModifier(
                contents: contents, changeDate: changeDate, commands: commands))
    }
}

/// See `sessionOverflow(contents:changeDate:commands:)`.
struct SessionOverflowModifier: ViewModifier {
    /// Which commands the menu holds, and the day its picker opens on.
    let contents: SessionMenuContents

    /// Moves the workout to another training day, or creates it on one.
    let changeDate: (Date) -> Void

    /// What the menu's other items do.
    let commands: SessionMenuCommands

    /// Whether the date sheet is open.
    @State private var isChangingDate = false

    /// The day its picker is on. Seeded when the sheet opens, so a cancel changes nothing and no
    /// write is issued per scroll tick.
    @State private var chosenDate = Date.now

    func body(content: Content) -> some View {
        content
            .toolbar {
                // `.primaryAction` rather than `.topBarTrailing`, and it is the spelling that
                // matters rather than the corner: the two agree on iOS, this is the one the free
                // workout's `⋯` already had, and `OUT-18.6` keeps that toolbar exactly. All three
                // hosts share it since `FR-18.4.8`, which is why there is no `side` to pass.
                ToolbarItem(placement: .primaryAction) {
                    if !contents.items.isEmpty {
                        SessionOverflowMenu(
                            contents: contents,
                            changeDate: {
                                // Today where there is no workout yet (`FR-18.7.1`): the sheet is
                                // offered exactly when the chosen day is what the session will be
                                // created on, and an unstarted day has no date of its own to open
                                // on.
                                chosenDate = contents.date ?? .now
                                isChangingDate = true
                            },
                            commands: commands)
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
