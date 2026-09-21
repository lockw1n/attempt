import Foundation
import Testing

@testable import Logging

/// Which commands a workout's overflow menu holds, in which state (`FR-17.9.7`, `FR-18.4.4`,
/// `FR-18.4.5`).
///
/// **The rule and each host's answer to it, because nothing can read a menu back.** Measured on
/// iOS 26.5 from a hosted screen: a toolbar's `UIMenu` holds a single `UIDeferredMenuElement`
/// until the menu has been opened, its button declines `accessibilityActivate()`, and a presented
/// menu's commands belong to a window the host does not own. So `DayView.menuContents` and
/// `ActiveSessionView.menuContents` exist to put each host's claim where a test can call it, on
/// `ScreenWakePolicy`'s rule (`T-1.96`) — that a decision written inside a `View` is reachable from
/// nothing. **That each body then passes its own function is held by review**, as `AttemptTests`'
/// launch sequence holds its two `.task` lines; what is not held by review is which command each
/// host asks for, which is here.
@Suite("A workout's overflow menu")
struct SessionMenuContentsTests {
    /// `FR-18.7.1` and `FR-18.7.2`, which is what `F-13` asked for: the day before its first
    /// answer is the one a lifter backdating last Thursday is looking at, and it carried one
    /// command.
    @Test("A day nobody has logged into offers Change date, Edit plan and Skip remaining")
    func anUnstartedDayOffersTheThreeThatNeedNoWorkout() {
        let contents = SessionMenuContents(
            date: nil,
            startsWhenDated: true,
            offersPlanEditing: true,
            offersSkipRemaining: true,
            destructive: .resetDay)

        #expect(contents.items == [.changeDate, .editPlan, .skipRemaining])
    }

    /// The empty day — a week's day whose routine prescribes nothing. There is nothing to answer
    /// and nothing to take back, and the two commands that need neither are still there.
    @Test("A day with no workout and no rows still offers Change date and Edit plan")
    func anEmptyUnstartedDayKeepsTheTwoThatNeedNoRows() {
        let contents = SessionMenuContents(
            date: nil,
            startsWhenDated: true,
            offersPlanEditing: true,
            offersSkipRemaining: false,
            destructive: .resetDay)

        #expect(contents.items == [.changeDate, .editPlan])
    }

    /// `FR-15.2.5`: a day whose routine has been archived is still a day of the week. Nothing can
    /// be started on it — ``DayStore/startIfNeeded(on:)`` has no routine to copy — so **Change
    /// date** would be an item that writes nothing, while **Edit plan** is exactly what the lifter
    /// needs. The two are separate parameters for this state and no other.
    @Test("A day in the week whose routine has gone offers Edit plan and not Change date")
    func anArchivedRoutineDayOffersThePlanAndNotTheDate() {
        let contents = SessionMenuContents(
            date: nil,
            startsWhenDated: false,
            offersPlanEditing: true,
            offersSkipRemaining: false,
            destructive: .resetDay)

        #expect(contents.items == [.editPlan])
    }

    @Test("A day with rows left offers all three, destructive last")
    func aPartAnsweredDayOffersAllThree() {
        let contents = SessionMenuContents(
            date: .now,
            startsWhenDated: true,
            offersPlanEditing: true,
            offersSkipRemaining: true,
            destructive: .resetDay)

        // **Edit plan** is gone, `Q-18.9` at (a): the day keeps the targets it started with
        // (`FR-17.10.5`), so an edit made now would change nothing on the screen behind the menu.
        #expect(contents.items == [.changeDate, .skipRemaining, .destructive(.resetDay)])
    }

    @Test("A day with nothing left to answer has no Skip remaining")
    func aFinishedDayDropsSkipRemaining() {
        let contents = SessionMenuContents(
            date: .now,
            startsWhenDated: true,
            offersPlanEditing: true,
            offersSkipRemaining: false,
            destructive: .resetDay)

        #expect(contents.items == [.changeDate, .destructive(.resetDay)])
    }

    @Test("A free workout offers Change date and its own destructive command")
    func aFreeWorkoutKeepsDiscard() {
        let contents = SessionMenuContents(
            date: .now,
            startsWhenDated: false,
            offersPlanEditing: false,
            offersSkipRemaining: false,
            destructive: .discardWorkout)

        #expect(contents.items == [.changeDate, .destructive(.discardWorkout)])
    }

    /// The free workout that has not been started, and the day whose stamp resolves to nothing.
    /// Neither can be dated into existence (`FR-18.7.1`) and neither has a plan to edit.
    @Test("A screen with no workout, no plan and nothing left to answer draws no menu at all")
    func anEmptyMenuIsNotDrawn() {
        let contents = SessionMenuContents(
            date: nil,
            startsWhenDated: false,
            offersPlanEditing: false,
            offersSkipRemaining: false,
            destructive: .discardWorkout)

        #expect(contents.items.isEmpty)
    }

    /// `FR-18.4.5`: one write, two promises. The words are the whole of what differs, so they are
    /// asserted as words rather than as which key they came from.
    @Test("The two destructive commands read differently")
    func theDestructiveCommandsAreNamedForWhatSurvives() {
        #expect(String(localized: SessionDestructiveCommand.resetDay.label) == "Reset day")
        #expect(
            String(localized: SessionDestructiveCommand.discardWorkout.label) == "Discard workout")
        #expect(
            String(localized: SessionDestructiveCommand.deleteWorkout.label) == "Delete workout")
    }

    // MARK: - What each host asks for

    /// `FR-18.4.4` and `FR-18.4.5` over the four states the day is ever in.
    ///
    /// **Including the day nobody has logged into**, which is the state the retiring foot used to
    /// answer: **Skip remaining** was drawn there, and a move that gated it on a workout would
    /// have dropped it rather than moved it (`FR-18.4.4` says it joins the menu).
    @Test("The planned day asks for Reset day, and for Skip remaining while a row is unanswered")
    func thePlannedDayAsksForResetDay() {
        let unanswered = DayProgress([Self.row(.unanswered), Self.row(.unanswered)])
        let answered = DayProgress([Self.row(.skipped), Self.row(.logged)])

        #expect(
            DayView.menuContents(
                date: nil,
                startsWhenDated: true,
                offersPlanEditing: true,
                progress: unanswered
            ).items == [.changeDate, .editPlan, .skipRemaining])
        #expect(
            DayView.menuContents(
                date: nil,
                startsWhenDated: true,
                offersPlanEditing: true,
                progress: DayProgress([])
            ).items == [.changeDate, .editPlan])
        #expect(
            DayView.menuContents(
                date: .now,
                startsWhenDated: true,
                offersPlanEditing: true,
                progress: unanswered
            ).items == [.changeDate, .skipRemaining, .destructive(.resetDay)])
        #expect(
            DayView.menuContents(
                date: .now,
                startsWhenDated: true,
                offersPlanEditing: true,
                progress: answered
            ).items == [.changeDate, .destructive(.resetDay)])
        #expect(
            DayView.menuContents(
                date: .now,
                startsWhenDated: true,
                offersPlanEditing: true,
                progress: DayProgress([])
            ).items == [.changeDate, .destructive(.resetDay)])
    }

    /// `FR-18.7.2` and `OUT-18.6` together: **Edit plan** never survives the day acquiring a
    /// workout, whichever way it acquired one — and a swap of the two new host answers would pass
    /// every assertion above that reads only the day.
    @Test("Edit plan is offered on no host once a workout exists, and on the free workout never")
    func editPlanIsTheOneCommandThatRetires() {
        let unanswered = DayProgress([Self.row(.unanswered)])

        #expect(
            DayView.menuContents(
                date: nil,
                startsWhenDated: true,
                offersPlanEditing: true,
                progress: unanswered
            ).items.contains(.editPlan))
        #expect(
            !DayView.menuContents(
                date: .now,
                startsWhenDated: true,
                offersPlanEditing: true,
                progress: unanswered
            ).items.contains(.editPlan))
        #expect(!ActiveSessionView.menuContents(date: nil).items.contains(.editPlan))
        #expect(!ActiveSessionView.menuContents(date: .now).items.contains(.editPlan))
    }

    /// `FR-18.7.1`: the free workout is the host that is *not* dated into existence. Its menu is
    /// empty before there is a workout, where the day's is not.
    @Test("Only the planned day offers Change date before there is a workout")
    func onlyTheDayIsDatedIntoExistence() {
        #expect(
            DayView.menuContents(
                date: nil,
                startsWhenDated: true,
                offersPlanEditing: true,
                progress: DayProgress([])
            ).items.contains(.changeDate))
        #expect(!ActiveSessionView.menuContents(date: nil).items.contains(.changeDate))
    }

    /// `OUT-18.6`: the free workout keeps the word it had, and gains nothing about a plan it does
    /// not have.
    @Test("The free workout asks for Discard, and never for Reset day or Skip remaining")
    func theFreeWorkoutAsksForDiscard() {
        #expect(ActiveSessionView.menuContents(date: nil).items.isEmpty)
        #expect(
            ActiveSessionView.menuContents(date: .now).items
                == [.changeDate, .destructive(.discardWorkout)])
    }

    /// `FR-18.7.3`: History's own host, and it is the first one whose menu is the same in both of
    /// its drawings — a past planned day and a past free workout get the same two commands,
    /// because the lifter does not know which they are looking at (`Q-18.3` at (a)).
    @Test("The past session asks for Change date and Delete workout, and nothing else")
    func thePastSessionAsksForDeleteWorkout() {
        #expect(
            PastSessionView.menuContents(date: .now, hasEnded: true).items
                == [.changeDate, .destructive(.deleteWorkout)])
        #expect(
            !PastSessionView.menuContents(date: .now, hasEnded: true).items
                .contains(.skipRemaining))
        #expect(
            !PastSessionView.menuContents(date: .now, hasEnded: true).items.contains(.editPlan))
    }

    /// The state every read of this screen passes through: loading, missing, failed. The route
    /// carries a session id, so a date before there is a session would be a date on a row nothing
    /// named — and an empty list is what stops the `⋯` being drawn at all.
    @Test("A past session that has not resolved draws no menu")
    func aPastSessionWithNoRecordDrawsNothing() {
        #expect(PastSessionView.menuContents(date: nil, hasEnded: false).items.isEmpty)
    }

    /// `FR-18.7.5` is about **a past session**, and this screen is reachable for one that is not:
    /// History lists open workouts (`FR-16.4.3`) and every row it draws links here, including the
    /// workout being logged today — the one ``ActiveSessionStore`` is holding and, for a free
    /// workout, *keeps* without reading again. Correcting it from here would leave that store
    /// publishing rows this screen had soft-deleted.
    ///
    /// **Both gates asserted apart**, because a menu that went away for the wrong reason is a
    /// menu that comes back for the wrong reason: the second line is the date gate on its own.
    @Test("A workout that has not ended draws no menu, though History lists it")
    func anOpenWorkoutDrawsNoMenu() {
        #expect(PastSessionView.menuContents(date: .now, hasEnded: false).items.isEmpty)
        #expect(PastSessionView.menuContents(date: nil, hasEnded: true).items.isEmpty)
        #expect(!PastSessionView.menuContents(date: .now, hasEnded: true).items.isEmpty)
    }

    /// `FR-18.7.5`'s last clause, and the one a swap of the three hosts' `destructive:` arguments
    /// would break silently: a past planned day is **Delete workout**, never **Reset day**. A week
    /// already over has no *upcoming* to return the plan to.
    @Test("The three hosts ask for three different destructive commands")
    func theThreeHostsDisagree() {
        let day = DayView.menuContents(
            date: .now,
            startsWhenDated: true,
            offersPlanEditing: true,
            progress: DayProgress([])
        ).items
        let free = ActiveSessionView.menuContents(date: .now).items
        let past = PastSessionView.menuContents(date: .now, hasEnded: true).items

        #expect(past.contains(.destructive(.deleteWorkout)))
        #expect(!past.contains(.destructive(.resetDay)))
        #expect(!past.contains(.destructive(.discardWorkout)))
        #expect(!day.contains(.destructive(.deleteWorkout)))
        #expect(!free.contains(.destructive(.deleteWorkout)))
    }

    /// A day's row in one state, for the counts ``DayProgress`` takes off them.
    ///
    /// - Parameter answer: What has been said about it.
    /// - Returns: The row.
    private static func row(_ answer: DayRowAnswer) -> DayRow {
        DayRow(id: UUID(), exercise: nil, plan: [], answer: answer)
    }

    /// The two hosts disagree, which is the whole of `FR-18.4.5` — and a swap would pass every
    /// assertion above that reads only one of them.
    @Test("The two hosts do not offer the same destructive command")
    func theHostsDisagree() {
        let day = DayView.menuContents(
            date: .now,
            startsWhenDated: true,
            offersPlanEditing: true,
            progress: DayProgress([])
        ).items
        let free = ActiveSessionView.menuContents(date: .now).items

        #expect(day.contains(.destructive(.resetDay)))
        #expect(free.contains(.destructive(.discardWorkout)))
        #expect(!day.contains(.destructive(.discardWorkout)))
        #expect(!free.contains(.destructive(.resetDay)))
    }
}
