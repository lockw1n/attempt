import Foundation
import Logging
import PowerliftingCore
import RepositoryInterface
import SwiftUI
import Testing
import UIKit

@testable import Attempt

/// `FR-18.5.1`'s surface: an **answered** row still draws a menu of its own, on a day that is over.
///
/// **What is in that menu is not askable from here, and this task measured it rather than assuming
/// it.** With the day answered, the tree published exactly
/// `Day options@340,257 / Day options@38,84 / More@38,84 / Done@349,84` — the row's `⋯`, the
/// toolbar's, the group iOS 26 puts it in, and Done. **Reset to unanswered** is in none of them,
/// before or after the row's menu is activated: `activate` reports the menu opened and the label is
/// still absent, a presented menu's commands belonging to a window the host does not own. That is
/// `T-18.09`'s toolbar measurement holding for a *content* menu too, so which commands the row
/// offers is asserted in `LoggingTests.DayRowMenuTests`, over `DayRowMenuContents`.
///
/// **What is askable is that the row keeps a menu once it is answered**, which is the half that can
/// regress here: the row's `⋯` is drawn beside the circle, and the circle goes away when the row is
/// answered (`FR-17.9.2`). A menu that went with it would leave `FR-18.5.1` reachable from nowhere
/// — exactly the shape `T-18.08` found the other way round on the toolbar.
///
/// **Serialized, for ``ScreenWiringTests``' reason**: the scene is shared.
@MainActor
@Suite("An answered row's own menu (FR-18.5.1)", .serialized)
struct DayRowMenuHostTests {
    /// What Done reads, which is how the toolbar's line is found.
    static let done = "Done"

    @Test("An answered row on a finished day still draws its own menu, off the toolbar's line")
    func anAnsweredRowKeepsItsMenu() async throws {
        let app = try await DayFixture()
        let screen = HostedScreen(NavigationStack { app.dayView() })
        defer { screen.dismantle() }
        // The rows arrive behind the day's own load, and how long that takes is the machine's: a
        // fixed settle was enough here and not on CI's runner.
        _ = await screen.settle { screen.activatableLabels().contains(DayFixture.circle) }

        try #require(
            !screen.accessibilityElements().isEmpty,
            Comment(rawValue: HostedScreen.accessibilityRemedy))
        // One exercise, so one circle answers the whole day and it ends (`FR-17.9.8`) — the state
        // the tester was stuck in, and the one the reset has to be reachable from.
        try #require(
            screen.activate(label: DayFixture.circle) == .activated,
            """
            the day drew no circle, so it was never in the unanswered state this starts from. What \
            it offers: \(screen.activatableLabels())
            """)
        // The answer is written behind the tap (`NFR-1.2`), so the state this is about arrives
        // later by an amount that is the machine's — see ``HostedScreen/settle(upTo:until:)``.
        try #require(
            await screen.settle { !screen.activatableLabels().contains(DayFixture.circle) },
            "the row never became answered, so this would assert about the wrong state")
        // Done is drawn by the same re-read that takes the circle away, and a turn after it.
        _ = await screen.settle { !screen.elements(labelled: Self.done).isEmpty }
        let bar = try #require(
            screen.elements(labelled: Self.done).first,
            "the day drew no Done, so there is no toolbar line to look along")
        // **And the row's own menu a turn after that**: the answered row is rebuilt, and for a turn
        // the tree holds the toolbar's menu alone — measured, `Menus at: [(20, 66, 36, 36)]` beside
        // a Done at the same 66. So the wait is for the claim itself, and a row that really has no
        // menu spends the whole bound and fails below with what the tree did hold.
        let offTheBar = {
            screen.elements(labelled: DayFixture.menu)
                .contains { $0.accessibilityFrame.midY != bar.accessibilityFrame.midY }
        }
        _ = await screen.settle(until: offTheBar)
        let menus = screen.elements(labelled: DayFixture.menu)
        #expect(
            menus.contains { $0.accessibilityFrame.midY != bar.accessibilityFrame.midY },
            """
            an answered row draws no menu of its own, so Reset to unanswered is reachable from \
            nowhere (FR-18.5.1). Menus at: \(menus.map(\.accessibilityFrame)), Done at \
            \(bar.accessibilityFrame).
            """)
    }
}
