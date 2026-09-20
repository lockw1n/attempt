import Foundation
import Logging
import PowerliftingCore
import RepositoryInterface
import SwiftUI
import Testing
import UIKit

@testable import Attempt

/// `FR-18.4`'s **Done**, on the two screens that carry it and absent from the one that does not.
///
/// **A toolbar is the class of thing this bundle exists for.** No content snapshot contains one —
/// this project renders the content view and never the navigation chrome — so a Done that was
/// never attached, or attached to a subview instead of the screen, would move no reference and
/// break no package test. Only a hosted view has a navigation bar to publish it from.
///
/// **What these tests cannot say is where Done goes**, and that is deliberate rather than missing:
/// `AttemptTests` does not link `AppNavigation` (`T-1.96`), so no fixture here can put a real shell
/// above the screen. Hosted bare, Done takes ``Logging``'s fallback and dismisses. The pop itself
/// is a plain type with its own tests — `LoggingTests.SessionExitTests` — which is the same split
/// `ExerciseCreationFromPickerTests` describes for the picker's exit.
///
/// **Serialized, for ``ScreenWiringTests``' reason**: the scene is shared and a second key window
/// mid-test changes what the first one's presentation does.
@MainActor
@Suite("Done, and the toolbar it is in (FR-18.4)", .serialized)
struct DoneButtonTests {
    /// What the button reads in `en`. A literal, because `LoggingStrings` is `internal` to its
    /// module and what is asserted here is what VoiceOver says rather than which key it came from.
    static let done = "Done"

    /// What the screen the day is pushed from is titled.
    static let rootTitle = "Week"

    /// What a back button to that screen can read.
    ///
    /// **Two spellings rather than one**, because iOS labels a back button with the previous
    /// screen's title and falls back to the word *Back* where that title is too long to fit. Which
    /// of the two arrives is a layout answer and is not the claim; that one of them is there at
    /// all is.
    static let backLabels: Set<String> = [rootTitle, "Back"]

    /// The day as it is actually reached — pushed onto a stack rather than hosted as its root.
    ///
    /// **A root has no back button**, and `FR-18.4.2` places the `⋯` *beside* one. Every other
    /// test here hosts its screen at a root, which is enough for "is this control on the screen"
    /// and is not enough for "what is it next to".
    struct PushedDay<Day: View>: View {
        /// The screen under test.
        let day: Day

        /// Pushed on the first layout pass, and never popped: what is under test is the pushed
        /// arrangement rather than the push.
        @State private var isPushed = true

        var body: some View {
            NavigationStack {
                Color.clear
                    .navigationTitle(DoneButtonTests.rootTitle)
                    .navigationDestination(isPresented: $isPushed) { day }
            }
        }
    }

    /// `FR-18.4.1`: the planned day names its exit.
    @Test("A planned day carries Done, and it answers")
    func theDayCarriesDone() async throws {
        let app = try await DayFixture()
        let screen = HostedScreen(NavigationStack { app.dayView() })
        defer { screen.dismantle() }
        await screen.settle()

        try #require(
            !screen.accessibilityElements().isEmpty,
            Comment(rawValue: HostedScreen.accessibilityRemedy))

        #expect(
            screen.activatableLabels().contains(Self.done),
            """
            the day has no Done in its toolbar (FR-18.4.1). What it offers: \
            \(screen.activatableLabels())
            """)
        #expect(
            screen.activate(label: Self.done) == .activated,
            "Done is in the day's toolbar and declined to answer")
    }

    /// `FR-18.4.3`: a past session carries it too, and `Q-18.3` puts it on both drawings — this is
    /// the free-workout one, which the question was *not* asked about.
    @Test("A past session carries Done, and it answers")
    func thePastSessionCarriesDone() async throws {
        let app = try await DayFixture()
        let sessionID = try await app.writeAFinishedFreeWorkout()
        let screen = HostedScreen(NavigationStack { app.pastSessionView(sessionID: sessionID) })
        defer { screen.dismantle() }
        await screen.settle()

        try #require(
            !screen.accessibilityElements().isEmpty,
            Comment(rawValue: HostedScreen.accessibilityRemedy))

        #expect(
            screen.activatableLabels().contains(Self.done),
            """
            the past session has no Done in its toolbar (FR-18.4.3). What it offers: \
            \(screen.activatableLabels())
            """)
        #expect(
            screen.activate(label: Self.done) == .activated,
            "Done is in the past session's toolbar and declined to answer")
    }

    /// `OUT-18.6`: the free workout keeps its toolbar exactly, which means **no Done**.
    ///
    /// **An absence is a claim about the whole tree**, so the `#require` above it is what separates
    /// "this screen does not draw Done" from "this destination publishes nothing at all" — the two
    /// read identically without it.
    @Test("A free workout in progress has no Done")
    func theFreeWorkoutHasNoDone() async throws {
        let app = try await DayFixture()
        try await app.startAFreeWorkout()
        let screen = HostedScreen(NavigationStack { app.activeSessionView() })
        defer { screen.dismantle() }
        await screen.settle()

        let labels = screen.activatableLabels()
        try #require(!labels.isEmpty, Comment(rawValue: HostedScreen.accessibilityRemedy))

        #expect(
            !labels.contains(Self.done),
            """
            the free workout grew a Done (OUT-18.6). It ends at Finish workout, and naming its exit \
            twice would name two different ones. What it offers: \(labels)
            """)
    }

    /// `FR-18.4.2`: the `⋯` moved leading, **beside Back**, and the only witness is where each
    /// is drawn.
    ///
    /// **Not the order the tree publishes them in, which is measured and is not a side.** The
    /// first version of this test asserted that the menu is read before Done, on the reasoning
    /// that VoiceOver sweeps from the leading edge; it passed unchanged with the menu put back
    /// trailing. SwiftUI publishes toolbar items in the order their modifiers were applied, and
    /// `.sessionOverflow` is applied above `.sessionDone` on both hosts — so the order says which
    /// modifier came first and nothing at all about the bar. The frame is what knows.
    ///
    /// **The day is answered first**, because the menu is drawn only once there is a workout to
    /// change the date of or discard — an unanswered day has neither (see `sessionOverflow`).
    /// Measured: with the day unanswered the only element labelled *Day options* is the **row's**
    /// menu, on the row's own line, and the bar carries Back and Done alone.
    ///
    /// **And the day is hosted pushed rather than as a stack's root**, which is the only
    /// arrangement that has a back button in it to be beside. The scope question this task carried
    /// was whether a `.topBarLeading` item *supplements* the back button on iOS 26 or *replaces*
    /// it; a screen hosted at a root answers neither, because there is no back button in its tree
    /// either way, so a leading item that had swallowed one would leave every assertion here
    /// green. Measured on iOS 26.5, pushed and answered: Back at x 16–60, the `⋯` at 76–112, Done
    /// at 317–382. That is what the `back` requirement below holds; the ordering expectations are
    /// the smaller half.
    @Test("The day's menu is drawn leading, beside Back, and Done trailing")
    func theMenuIsLeadingOfDone() async throws {
        let app = try await DayFixture()
        let screen = HostedScreen(PushedDay(day: app.dayView()))
        defer { screen.dismantle() }
        await screen.settle(turns: 8)

        try #require(
            !screen.accessibilityElements().isEmpty,
            Comment(rawValue: HostedScreen.accessibilityRemedy))
        try #require(
            screen.activate(label: DayFixture.circle) == .activated,
            """
            the day drew no circle to answer, so it has no workout and the toolbar's menu is not \
            drawn at all. What it offers: \(screen.activatableLabels())
            """)
        await screen.settle()

        let done = try #require(
            screen.elements(labelled: Self.done).first,
            """
            the day drew no Done, so there is nothing to place the menu against. The screen \
            offers: \(screen.activatableLabels())
            """)
        let bar = done.accessibilityFrame
        // The bar's `⋯`, not the row's: both read *Day options*, and the one being placed is the
        // one drawn on the same line as Done.
        let menu = try #require(
            screen.elements(labelled: DayFixture.menu).first(where: {
                $0.accessibilityFrame.midY == bar.midY
            }),
            """
            the day drew no overflow menu on the bar, so there is no side for it to be on. Menus \
            at: \(screen.elements(labelled: DayFixture.menu).map(\.accessibilityFrame))
            """)
        let back = try #require(
            screen.accessibilityElements().first(where: {
                Self.backLabels.contains($0.accessibilityLabel ?? "")
                    && $0.accessibilityTraits.contains(.button)
            }),
            """
            the pushed day published no back button, so the leading `⋯` replaced it rather than \
            joining it (FR-18.4.2) — and Back is no longer a way out of the day. What the screen \
            offers: \(screen.activatableLabels())
            """)

        #expect(
            menu.accessibilityFrame.maxX <= bar.minX,
            """
            the menu is not leading of Done (FR-18.4.2). Menu at \(menu.accessibilityFrame), \
            Done at \(bar).
            """)
        #expect(
            back.accessibilityFrame.maxX <= menu.accessibilityFrame.minX,
            """
            the menu is not beside Back but in front of it (FR-18.4.2). Back at \
            \(back.accessibilityFrame), menu at \(menu.accessibilityFrame).
            """)
    }

    /// `FR-18.4.1`: Done writes nothing, with every row unanswered.
    ///
    /// **The counter is over the repository rather than over the store**, because a Done that
    /// ended the session would go through the store and a Done that stamped the day would not —
    /// the claim is that *nothing reaches storage*, which is one layer down.
    @Test("Done writes nothing on a day with every row unanswered")
    func doneWritesNothingWithRowsUnanswered() async throws {
        let app = try await DayFixture()
        let screen = HostedScreen(NavigationStack { app.dayView() })
        defer { screen.dismantle() }
        await screen.settle()

        try #require(
            !screen.accessibilityElements().isEmpty,
            Comment(rawValue: HostedScreen.accessibilityRemedy))
        // Nothing has been answered, so nothing has been written: the session is created by the
        // first answer and not by the screen opening (`FR-17.9.5`).
        try #require(await app.writes.written.isEmpty)

        #expect(screen.activate(label: Self.done) == .activated)
        await screen.settle()

        let after = await app.writes.count
        #expect(
            after == 0,
            """
            Done wrote \(after) time(s) on an unanswered day. It is not a Finish and must not \
            become one (FR-18.4.1, D-17.6): a day left part-answered is the card that says \
            Continue.
            """)
    }

    /// `FR-18.4.1`: and writes nothing with every row answered either — the state a Done that had
    /// quietly become a Finish would be tempted by.
    @Test("Done writes nothing on a day with every row answered")
    func doneWritesNothingWithRowsAnswered() async throws {
        let app = try await DayFixture()
        let screen = HostedScreen(NavigationStack { app.dayView() })
        defer { screen.dismantle() }
        await screen.settle()

        try #require(
            !screen.accessibilityElements().isEmpty,
            Comment(rawValue: HostedScreen.accessibilityRemedy))
        // The day is one exercise, so one circle answers all of it (`FR-17.9.2`).
        try #require(
            screen.activate(label: DayFixture.circle) == .activated,
            """
            the day drew no circle to answer, so this test would assert about the unanswered state \
            twice. What it offers: \(screen.activatableLabels())
            """)
        await screen.settle()

        let answered = await app.writes.count
        try #require(answered > 0, "answering the day wrote nothing, so the counter proves nothing")

        #expect(screen.activate(label: Self.done) == .activated)
        await screen.settle()

        let after = await app.writes.count
        #expect(
            after == answered,
            """
            Done wrote \(after - answered) time(s) on a finished day. The day is finished at its \
            last answer (FR-17.9.5); Done is navigation (FR-18.4.1, D-17.6).
            """)
    }
}

/// Counts what reaches storage, and forwards everything unchanged.
///
/// **A decorator rather than a fake**, because the screens under it have to work: a day that could
/// not read its plan would draw the empty state, and Done writing nothing there is a claim about
/// nothing. Every read goes to the real in-memory store; every write is counted on its way.
struct CountingWorkoutRepository: WorkoutRepository, PlannedTargetRepository, Sendable {
    /// What the screen actually reads and writes through.
    let wrapped: any WorkoutRepository & PlannedTargetRepository

    /// How many writes have gone past.
    let writes: WriteCounter

    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        try await wrapped.sessions(in: range, includingDeleted: includingDeleted)
    }

    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        try await wrapped.session(id: id, includingDeleted: includingDeleted)
    }

    func sessions(
        forProgramRunID runID: UUID, week: Int, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        try await wrapped.sessions(
            forProgramRunID: runID, week: week, includingDeleted: includingDeleted)
    }

    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        try await wrapped.entries(forSessionID: sessionID, includingDeleted: includingDeleted)
    }

    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? {
        try await wrapped.entry(id: id, includingDeleted: includingDeleted)
    }

    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }

    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }

    func plannedTargets(
        forEntryID entryID: UUID, includingDeleted: Bool
    ) async throws -> [PlannedTargetGroup] {
        try await wrapped.plannedTargets(forEntryID: entryID, includingDeleted: includingDeleted)
    }

    func save(_ session: WorkoutSession) async throws {
        await writes.record("save(WorkoutSession)")
        try await wrapped.save(session)
    }

    func save(_ entry: ExerciseEntry) async throws {
        await writes.record("save(ExerciseEntry)")
        try await wrapped.save(entry)
    }

    func save(_ set: SetEntry) async throws {
        await writes.record("save(SetEntry)")
        try await wrapped.save(set)
    }

    func save(_ group: PlannedTargetGroup) async throws {
        await writes.record("save(PlannedTargetGroup)")
        try await wrapped.save(group)
    }

    func deleteSession(id: UUID) async throws {
        await writes.record("deleteSession")
        try await wrapped.deleteSession(id: id)
    }

    func deleteExerciseEntry(id: UUID) async throws {
        await writes.record("deleteExerciseEntry")
        try await wrapped.deleteExerciseEntry(id: id)
    }

    func deleteSet(id: UUID) async throws {
        await writes.record("deleteSet")
        try await wrapped.deleteSet(id: id)
    }
}

/// The tally, and what was written — the names are what makes a failure readable.
actor WriteCounter {
    /// One entry per write, in the order they went past.
    private(set) var written: [String] = []

    /// How many there have been.
    var count: Int { written.count }

    /// Notes one.
    ///
    /// - Parameter what: Which write it was.
    func record(_ what: String) {
        written.append(what)
    }
}
