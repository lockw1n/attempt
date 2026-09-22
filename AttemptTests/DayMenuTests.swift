import Foundation
import Logging
import PowerliftingCore
import RepositoryInterface
import SwiftUI
import Testing
import UIKit

@testable import Attempt

/// `FR-18.4.4`'s **Skip remaining** where the day has no workout yet — the one claim about the
/// day's menu that only a host can make.
///
/// **What is in the menu is not askable from here, and that is measured rather than assumed.** On
/// iOS 26.5 a toolbar's `UIMenu` holds a single `UIDeferredMenuElement` until the menu has been
/// opened; its button declines `accessibilityActivate()` (it raises its menu on touch-down, which
/// VoiceOver's double-tap is not) and is not a `UIButton`, so nothing here opens it either; and a
/// menu that *is* open publishes its commands into a window the host does not own. So which
/// commands each host asks for is asserted in `LoggingTests.SessionMenuContentsTests`, over the
/// functions the two bodies call.
///
/// **What is askable here is whether the `⋯` is drawn at all**, which is the half `T-18.08`
/// measured the other way round: with the day unanswered, the only element reading *Day options*
/// was the **row's**, and the bar's appeared once a circle was pressed. `FR-18.4.4` changes that —
/// **Skip remaining** answers rows rather than a workout, and on a day never started it is the
/// first answer, so the bar carries a menu from the first moment. A gate that had kept the old
/// rule would leave that command reachable from nowhere on this screen.
///
/// **Serialized, for ``ScreenWiringTests``' reason**: the scene is shared and a second key window
/// mid-test changes what the first one's presentation does.
@MainActor
@Suite("The day's `⋯` before the day has a workout (FR-18.4.4)", .serialized)
struct DayMenuTests {
    /// What Done reads, which is how the toolbar's own line is found.
    static let done = "Done"

    @Test("An unanswered day draws the overflow menu in its toolbar")
    func anUnansweredDayDrawsTheBarMenu() async throws {
        let app = try await DayFixture()
        let screen = HostedScreen(NavigationStack { app.dayView() })
        defer { screen.dismantle() }
        await screen.settle()

        try #require(
            !screen.accessibilityElements().isEmpty,
            Comment(rawValue: HostedScreen.accessibilityRemedy))
        try #require(
            screen.activatableLabels().contains(DayFixture.circle),
            """
            the day drew no circle, so it is not in the unanswered state this test is about. What \
            it offers: \(screen.activatableLabels())
            """)
        let bar = try #require(
            screen.elements(labelled: Self.done).first,
            "the day drew no Done, so there is no toolbar line to look along")

        // Both the bar's `⋯` and a row's read *Day options*; the one under test is the one on
        // Done's line, which is what `DoneButtonTests.bar(of:requirement:)` disambiguates by too.
        let menus = screen.elements(labelled: DayFixture.menu)
        #expect(
            menus.contains { $0.accessibilityFrame.midY == bar.accessibilityFrame.midY },
            """
            an unanswered day draws no menu in its toolbar, so Skip remaining is reachable from \
            nowhere on this screen (FR-18.4.4) — it left the foot in this task. Menus at: \
            \(menus.map(\.accessibilityFrame)), Done at \(bar.accessibilityFrame).
            """)
    }
}
