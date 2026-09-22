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
/// **The exit is a checkmark and is still found by the word** (`FR-18.4.7`): the platform's
/// confirm role draws the glyph and keeps the button's name, so every assertion below reads
/// ``done`` exactly as it did while the word was on screen. A glyph that had taken the label with
/// it would fail here rather than in a picture, which is the point of leaving these unchanged.
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

    /// How far across the bar a control has to start before it is on the trailing side.
    ///
    /// **A fraction of the hosted width rather than a point count**, because the claim is about a
    /// side and the bar's width is the device's. Half is the honest reading of *trailing*, and it
    /// is what separates the two arrangements: measured on iOS 26.5, leading the `⋯` starts at
    /// 76 pt of 402 and trailing it starts at 278.
    static let trailingHalf = 0.5

    /// The least distance, in points, between the `⋯` and the exit that still reads as two
    /// controls rather than one glass group (`FR-18.4.8`).
    ///
    /// **Measured, and set below the measurement rather than at it**: 20 pt on iOS 26.5, on both
    /// hosts. A threshold at the measured figure would fail on the first bar that spaces its
    /// items differently.
    ///
    /// **What this does not witness is the `ToolbarSpacer`.** Probed: removing it left both
    /// frames and the gap unchanged, because the two items reach the bar from two different
    /// `.toolbar` modifiers and iOS 26 fuses only what one toolbar builder contributes. So this
    /// holds the *arrangement* — two controls with air between them — and the spacer that
    /// declares the intent is held by review alone.
    static let separation = 8.0

    /// `G-4.3`'s 44 pt floor, held on the exit's **width** and on nothing else here.
    ///
    /// **Not the square.** Measured on iOS 26.5: every SwiftUI item on this bar lays out 36 pt
    /// tall — the exit and the `⋯` alike — and only Back, which is UIKit's, is 44 × 44. The
    /// height is the bar's and no host can raise it, so a test that asked for the square would
    /// be asking for something no code here can give.
    ///
    /// **And the exit alone.** The `⋯` is 36 pt wide and has been since `T-18.08` put it on the
    /// bar; moving it is not this task's, and asserting it here would fail on code nobody is
    /// changing. The exit is: it went from the 64 pt word to a 28 pt checkmark, and what carries
    /// it back over the line is the minimum `sessionDone(label:)` imposes.
    static let touchTarget = 44.0

    /// The three controls a workout screen's bar carries, and the width they sit across.
    ///
    /// **One arrangement on two screens** (`FR-18.4.8`, `FR-18.7.3`), so finding the controls and
    /// asking where they are is written once here and reached twice. What each host does *not*
    /// share is how it gets to the state: the day has to be answered before its `⋯` is drawn at
    /// all, and the past session does not.
    struct Bar {
        /// The back button, under whichever of its two labels arrived.
        let back: CGRect

        /// The bar's `⋯` — the one on the exit's line, a row's menu reading the same word.
        let menu: CGRect

        /// The exit, found by its **name** and not by its glyph (`FR-18.4.7`).
        let exit: CGRect

        /// What the screen laid out at, which is what *trailing* is a fraction of.
        let width: CGFloat
    }

    /// Reads the three off a settled screen.
    ///
    /// - Parameters:
    ///   - screen: The host, settled, and on the day already answered.
    ///   - requirement: The ID the diagnostics cite; the two hosts carry different ones.
    /// - Returns: The three frames, and the width they are across.
    static func bar(of screen: HostedScreen, requirement: String) throws -> Bar {
        let exit = try #require(
            screen.elements(labelled: done).first,
            """
            no exit named \(done) (\(requirement)), so there is nothing to place the menu \
            against — and a checkmark that lost its name is what FR-18.4.7 forbids. The screen \
            offers: \(screen.activatableLabels())
            """)
        let menus = screen.elements(labelled: DayFixture.menu)
        let menu = try #require(
            menus.first(where: { $0.accessibilityFrame.midY == exit.accessibilityFrame.midY }),
            """
            no overflow menu on the bar (\(requirement)), so there is no side for it to be on. \
            Menus at: \(menus.map(\.accessibilityFrame)), exit at \(exit.accessibilityFrame).
            """)
        let back = try #require(
            screen.accessibilityElements().first(where: {
                backLabels.contains($0.accessibilityLabel ?? "")
                    && $0.accessibilityTraits.contains(.button)
            }),
            """
            no back button (\(requirement)): the leading corner is its alone now, and a bar \
            without it is a screen with no swipe back. What it offers: \
            \(screen.activatableLabels())
            """)
        let width = screen.controller.view.bounds.width
        try #require(width > 0, "the screen laid out at no width, so no side means anything")
        return Bar(
            back: back.accessibilityFrame,
            menu: menu.accessibilityFrame,
            exit: exit.accessibilityFrame,
            width: width)
    }

    /// `FR-18.4.8`'s arrangement, over what ``bar(of:requirement:)`` read.
    ///
    /// - Parameters:
    ///   - bar: The three frames.
    ///   - requirement: The ID the diagnostics cite.
    static func expectTrailingArrangement(_ bar: Bar, requirement: String) {
        #expect(
            bar.menu.minX >= bar.width * trailingHalf,
            """
            the menu is not on the trailing side (\(requirement)) — it starts at \(bar.menu.minX) \
            of \(bar.width). Menu at \(bar.menu), exit at \(bar.exit), Back at \(bar.back).
            """)
        #expect(
            bar.menu.maxX <= bar.exit.minX,
            "the menu is not left of the exit (\(requirement)). Menu \(bar.menu), exit \(bar.exit).")
        #expect(
            bar.exit.minX - bar.menu.maxX >= separation,
            """
            the menu and the exit are one control rather than two (\(requirement)): \
            \(bar.exit.minX - bar.menu.maxX) pt between them. Probed: the gap survives the \
            ToolbarSpacer being removed and dies when the two modifiers are swapped, so what this \
            holds is the arrangement.
            """)
        #expect(
            bar.back.maxX <= bar.menu.minX,
            "Back is not leading of the menu (\(requirement)). Back \(bar.back), menu \(bar.menu).")
        #expect(
            bar.exit.width >= touchTarget,
            """
            the exit is under G-4.3's 44 pt floor (\(requirement)): \(bar.exit.width) pt wide. \
            A glyph is narrower than the word it replaced — 28 pt against 64 — and the only \
            thing over the line is the minimum sessionDone(label:) imposes. Exit at \(bar.exit).
            """)
    }

    /// The day as it is actually reached — pushed onto a stack rather than hosted as its root.
    ///
    /// **A root has no back button**, and the leading corner is Back's alone now (`FR-18.4.8`).
    /// Every other test here hosts its screen at a root, which is enough for "is this control on
    /// the screen" and is not enough for "what is it next to" — nor for whether Back is still
    /// there at all once a leading item has been taken away.
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

    /// `FR-18.4.8`: the `⋯` moved **trailing**, left of the exit and a control of its own, and
    /// the leading corner is Back's alone again.
    ///
    /// **"Left of the exit" is not a witness of a side, and was not one before either.** It was
    /// true while the menu was leading — everything on a bar is left of its trailing corner — so
    /// an assertion built only from it passes in both arrangements, which is the same shape
    /// `T-18.08` found when it first asserted the *publication order* and put the menu back
    /// trailing with nothing failing. Probed here the same way: with the menu forced back to
    /// `.topBarLeading` this expectation still passes and ``trailingHalf`` is what fails. What
    /// tells the two apart is where the menu sits across the bar's width.
    ///
    /// **And a gap, because `FR-18.4.8` asks for two controls rather than one group.** Measured
    /// on iOS 26.5, pushed and answered, on a 402 pt bar: Back at x 16–60, the `⋯` at 278–314,
    /// the exit at 334–382 — 20 pt between the two. See ``separation`` for what that expectation
    /// does and does not hold, and ``touchTarget`` for why the exit is 48 pt wide rather than the
    /// 28 the bare glyph laid out at.
    ///
    /// **The day is answered first**, because the menu is drawn only once there is a workout to
    /// change the date of or discard — an unanswered day has neither (see `sessionOverflow`).
    ///
    /// **And the day is hosted pushed rather than as a stack's root**, which is the only
    /// arrangement that has a back button in it at all. Nothing is placed leading any more, so
    /// what that arrangement now holds is the other half of the same claim: Back survived the
    /// removal, and the swipe it belongs to has something to pop.
    @Test("The day's menu is drawn trailing, left of the exit and separate from it")
    func theMenuIsTrailingOfTheExit() async throws {
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

        Self.expectTrailingArrangement(
            try Self.bar(of: screen, requirement: "FR-18.4.8"), requirement: "FR-18.4.8")
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
