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
    @Test("A day nobody has logged into offers Skip remaining and nothing that needs a workout")
    func anUnstartedDayOffersSkipRemainingAlone() {
        let contents = SessionMenuContents(
            date: nil, offersSkipRemaining: true, destructive: .resetDay)

        #expect(contents.items == [.skipRemaining])
    }

    @Test("A day with rows left offers all three, destructive last")
    func aPartAnsweredDayOffersAllThree() {
        let contents = SessionMenuContents(
            date: .now, offersSkipRemaining: true, destructive: .resetDay)

        #expect(contents.items == [.changeDate, .skipRemaining, .destructive(.resetDay)])
    }

    @Test("A day with nothing left to answer has no Skip remaining")
    func aFinishedDayDropsSkipRemaining() {
        let contents = SessionMenuContents(
            date: .now, offersSkipRemaining: false, destructive: .resetDay)

        #expect(contents.items == [.changeDate, .destructive(.resetDay)])
    }

    @Test("A free workout offers Change date and its own destructive command")
    func aFreeWorkoutKeepsDiscard() {
        let contents = SessionMenuContents(
            date: .now, offersSkipRemaining: false, destructive: .discardWorkout)

        #expect(contents.items == [.changeDate, .destructive(.discardWorkout)])
    }

    @Test("A screen with no workout and nothing left to answer draws no menu at all")
    func anEmptyMenuIsNotDrawn() {
        let contents = SessionMenuContents(
            date: nil, offersSkipRemaining: false, destructive: .discardWorkout)

        #expect(contents.items.isEmpty)
    }

    /// `FR-18.4.5`: one write, two promises. The words are the whole of what differs, so they are
    /// asserted as words rather than as which key they came from.
    @Test("The two destructive commands read differently")
    func theDestructiveCommandsAreNamedForWhatSurvives() {
        #expect(String(localized: SessionDestructiveCommand.resetDay.label) == "Reset day")
        #expect(
            String(localized: SessionDestructiveCommand.discardWorkout.label) == "Discard workout")
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
            DayView.menuContents(date: nil, progress: unanswered).items == [.skipRemaining])
        #expect(
            DayView.menuContents(date: .now, progress: unanswered).items
                == [.changeDate, .skipRemaining, .destructive(.resetDay)])
        #expect(
            DayView.menuContents(date: .now, progress: answered).items
                == [.changeDate, .destructive(.resetDay)])
        #expect(
            DayView.menuContents(date: .now, progress: DayProgress([])).items
                == [.changeDate, .destructive(.resetDay)])
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
        let day = DayView.menuContents(date: .now, progress: DayProgress([])).items
        let free = ActiveSessionView.menuContents(date: .now).items

        #expect(day.contains(.destructive(.resetDay)))
        #expect(free.contains(.destructive(.discardWorkout)))
        #expect(!day.contains(.destructive(.discardWorkout)))
        #expect(!free.contains(.destructive(.resetDay)))
    }
}
