import Foundation
import Logging
import SwiftUI
import Testing

@testable import Attempt

/// `FR-18.7.3`'s `⋯` on `history.session` — that it is drawn at all, and where (`F-14`).
///
/// **A toolbar is the class of thing this bundle exists for**, which is ``DoneButtonTests``' whole
/// argument carried onto the third host: no content snapshot contains a navigation bar, so a menu
/// that was never attached — or attached to the scroller instead of the screen — would move no
/// reference and break no package test.
///
/// **What is *in* the menu is not asserted here and cannot be.** Measured twice on iOS 26.5
/// (`T-18.09` on a toolbar, `T-18.10` on a content menu): a toolbar's `UIMenu` holds one
/// `UIDeferredMenuElement` until it has been opened, and its button declines
/// `accessibilityActivate()`. Which commands this host asks for is
/// `LoggingTests.SessionMenuContentsTests` — the seam exists for exactly this reason. What a host
/// can still see is whether the control is drawn, and that regresses on its own.
///
/// **Serialized, for ``ScreenWiringTests``' reason**: the scene is shared.
@MainActor
@Suite("The past session's overflow menu (FR-18.7.3)", .serialized)
struct PastSessionMenuTests {
    /// `Q-18.3` at (a): the free workout's drawing carries it.
    @Test("A past free workout carries the overflow menu")
    func aPastFreeWorkoutCarriesTheMenu() async throws {
        let app = try await DayFixture()
        let sessionID = try await app.writeAFinishedFreeWorkout()
        let screen = HostedScreen(NavigationStack { app.pastSessionView(sessionID: sessionID) })
        defer { screen.dismantle() }
        await screen.settle()

        let labels = screen.activatableLabels()
        try #require(!labels.isEmpty, Comment(rawValue: HostedScreen.accessibilityRemedy))

        #expect(
            labels.contains(DayFixture.menu),
            """
            a past free workout has no overflow menu (FR-18.7.3), so there is no way to change its \
            date or delete it. What it offers: \(labels)
            """)
    }

    /// And the planned one — the drawing `Q-18.3` was asked about, and the one where the menu's
    /// destructive command had to be a third word rather than **Reset day** (`FR-18.7.5`).
    ///
    /// **It is the menu *on the bar* that is required, not a menu with that label.** A past planned
    /// day draws the checklist's rows, each with a `⋯` of its own carrying **Log** (`T-18.10`), and
    /// every one of them reads *Day options* as well — so the shape
    /// ``aPastFreeWorkoutCarriesTheMenu()`` uses, `labels.contains(_:)`, would be satisfied here by
    /// a row even with the toolbar's modifier deleted. That shape is sound on the free workout,
    /// whose cards carry no menu at all (measured: removing the modifier fails it), and unsound on
    /// this drawing. `T-18.16`'s rule with the state present and unobservable rather than absent —
    /// and the `#require` below is what keeps the premise honest if the rows ever lose theirs.
    @Test("A past planned day carries the overflow menu too, on the bar and not only on its rows")
    func aPastPlannedDayCarriesTheMenu() async throws {
        let app = try await DayFixture()
        let sessionID = try await app.writeAFinishedPlannedDay()
        let screen = HostedScreen(NavigationStack { app.pastSessionView(sessionID: sessionID) })
        defer { screen.dismantle() }
        await screen.settle()

        try #require(
            !screen.accessibilityElements().isEmpty,
            Comment(rawValue: HostedScreen.accessibilityRemedy))
        let bar = try #require(
            screen.elements(labelled: DoneButtonTests.done).first,
            """
            the past session drew no Done, so there is no bar to tell the toolbar's menu from the \
            rows'. The screen offers: \(screen.activatableLabels())
            """
        ).accessibilityFrame
        let menus = screen.elements(labelled: DayFixture.menu)
        // The rows' own menus are what makes this assertion worth making: with none of them drawn,
        // "there is a menu somewhere" would have been the same claim as "there is one on the bar".
        try #require(
            menus.contains { $0.accessibilityFrame.midY != bar.midY },
            """
            the planned day drew no row menus, so this test cannot tell the toolbar's `⋯` from a \
            row's and would pass either way (FR-17.7.6, T-18.10).
            """)

        #expect(
            menus.contains { $0.accessibilityFrame.midY == bar.midY },
            """
            a past planned day has no overflow menu on its bar (FR-18.7.3). The two drawings carry \
            the same toolbar, because the lifter does not know which they are in (Q-18.3). Menus \
            at: \(menus.map(\.accessibilityFrame)), Done at \(bar).
            """)
    }

    /// `FR-18.7.3` names a **side**, and the only witness is where each control is drawn — not the
    /// order the tree publishes them in, which ``DoneButtonTests/theMenuIsLeadingOfDone()`` measured
    /// and found to say only which modifier was applied first.
    ///
    /// **Hosted pushed rather than at a root**, for that test's reason: a root has no back button,
    /// so a leading item that had swallowed one would leave every assertion green.
    @Test("The past session's menu is drawn leading, beside Back, and Done trailing")
    func theMenuIsLeadingOfDone() async throws {
        let app = try await DayFixture()
        let sessionID = try await app.writeAFinishedPlannedDay()
        let screen = HostedScreen(
            DoneButtonTests.PushedDay(day: app.pastSessionView(sessionID: sessionID)))
        defer { screen.dismantle() }
        await screen.settle(turns: 8)

        try #require(
            !screen.accessibilityElements().isEmpty,
            Comment(rawValue: HostedScreen.accessibilityRemedy))

        let done = try #require(
            screen.elements(labelled: DoneButtonTests.done).first,
            """
            the past session drew no Done, so there is nothing to place the menu against. The \
            screen offers: \(screen.activatableLabels())
            """)
        let bar = done.accessibilityFrame
        // The bar's `⋯` and not a row's: this screen has one of those too (`T-18.10`, **Log**
        // alone), and both read the same label. The one being placed is on Done's line.
        let menu = try #require(
            screen.elements(labelled: DayFixture.menu).first(where: {
                $0.accessibilityFrame.midY == bar.midY
            }),
            """
            the past session drew no overflow menu on the bar, so there is no side for it to be \
            on. Menus at: \(screen.elements(labelled: DayFixture.menu).map(\.accessibilityFrame))
            """)
        let back = try #require(
            screen.accessibilityElements().first(where: {
                DoneButtonTests.backLabels.contains($0.accessibilityLabel ?? "")
                    && $0.accessibilityTraits.contains(.button)
            }),
            """
            the pushed past session published no back button, so the leading `⋯` replaced it \
            rather than joining it (FR-18.7.3) — and Back is no longer a way out. What the screen \
            offers: \(screen.activatableLabels())
            """)

        #expect(
            menu.accessibilityFrame.maxX <= bar.minX,
            """
            the menu is not leading of Done (FR-18.7.3). Menu at \(menu.accessibilityFrame), \
            Done at \(bar).
            """)
        #expect(
            back.accessibilityFrame.maxX <= menu.accessibilityFrame.minX,
            """
            the menu is not beside Back but in front of it (FR-18.7.3). Back at \
            \(back.accessibilityFrame), menu at \(menu.accessibilityFrame).
            """)
    }
}
