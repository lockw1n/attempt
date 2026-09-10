import Foundation
import Logging
import PowerliftingCore
import RepositoryInterface
import SwiftUI
import Testing

@testable import Attempt

/// That a screen's parts are still wired to the screen (`TR-1.12`, `DOD-17.6`).
///
/// **The defect this exists for.** `T-17.11` deleted two modifiers from `ActiveSessionView` — the
/// `.sheet(item:)` that raises the set editor and the `.onChange` that follows the note draft — and
/// the compiler, `swift test`, every snapshot reference and the screen-inventory row were all
/// silent. `T-17.01` found it by using the app. A reference pictures a subtree; a presentation
/// belongs to the host, so the parts kept rendering exactly as pictured while the screen no longer
/// did anything with them. **A screen whose only proof is a reference of one of its parts has no
/// proof the parts are still wired together.**
///
/// **What it does not cover, in `check-doc-links.sh`'s own words for its own blind spot.** That
/// script says extraction reads the built module, so a link in a `private` member's doc comment is
/// not in the graph and is never checked, whatever `--minimum-access-level` says. Here: activation
/// reads the accessibility tree, so **a control that publishes no accessibility element is not in
/// the tree and is never checked, whatever the screen draws** — and neither is a control that is in
/// the tree but covered, mis-sized, or behind a gesture that wins. This proves that a screen's parts
/// are still wired to the screen, never that they can be touched.
@MainActor
@Suite("Screen wiring (TR-1.12)")
struct ScreenWiringTests {
    /// Tapping a card's Log control raises the set editor over the workout.
    ///
    /// The fixture is the app's own composition root over an in-memory store, so what is exercised
    /// is the screen as `RootTabView` builds it rather than a hand-assembled copy of it — T-16.17's
    /// finding, that a fixture assembling a shared component's parts is a second place the screen's
    /// decision lives.
    @Test("The active session's Log control presents the set editor")
    func theLogControlPresentsTheSetEditor() async throws {
        let fixture = try await SessionFixture()
        let screen = HostedScreen(
            ActiveSessionView(
                store: fixture.store,
                vocabulary: fixture.dependencies.modifiers,
                equipment: fixture.dependencies.equipment
            )
        )
        defer { screen.dismantle() }
        await screen.settle()

        // First, and separately: an empty tree is the destination's fault and must not be
        // reported as the screen's. `#require` rather than `#expect` — every assertion below is
        // meaningless once this one has failed.
        try #require(!screen.accessibilityElements().isEmpty, "\(HostedScreen.accessibilityRemedy)")
        #expect(screen.presented == nil, "nothing may be presented before the control is used")

        let label = LoggingCopy.string(forKey: "logging.session.set.add.action")
        let found = screen.activate(label: label)
        #expect(
            found,
            """
            no activatable element labelled "\(label)". \
            What the screen published: \(screen.activatableLabels())
            """)
        await screen.settle()

        // The assertion the deleted `.sheet(item:)` fails. Anchored to a literal rather than to a
        // second read of the same property: `presented != nil` is the whole claim, and there is no
        // other way for this screen to put a controller on top of itself.
        #expect(screen.presented != nil, "the Log control did not raise the set editor")
    }

    /// The screen publishes the controls the workout's states are supposed to offer.
    ///
    /// A weaker claim than the one above and a different instrument: this is the accessibility tree
    /// existing at all, which is what `T-1.82`'s two surviving modifier mutations need and what a
    /// bare SwiftPM bundle cannot produce (T-1.08 measured `UIHostingController` rendering no view
    /// hierarchy without a scene).
    @Test("A hosted active session publishes an accessibility tree with controls in it")
    func aHostedSessionPublishesAnAccessibilityTree() async throws {
        let fixture = try await SessionFixture()
        let screen = HostedScreen(
            ActiveSessionView(
                store: fixture.store,
                vocabulary: fixture.dependencies.modifiers,
                equipment: fixture.dependencies.equipment
            )
        )
        defer { screen.dismantle() }
        await screen.settle()

        try #require(!screen.accessibilityElements().isEmpty, "\(HostedScreen.accessibilityRemedy)")
        #expect(
            !screen.activatableLabels().isEmpty,
            "the tree exists but holds no control:\n\(screen.describeHierarchy())")
    }
}

/// A workout in progress holding one exercise, built through the app's own wiring.
@MainActor
struct SessionFixture {
    /// The stores `RootTabView` would hand the screen.
    let dependencies: AppDependencies.Stores

    /// The workout in progress.
    var store: ActiveSessionStore { dependencies.activeSession }

    /// Opens an in-memory store, starts a workout and puts one exercise in it.
    init() async throws {
        let app = AppDependencies.preview
        guard case .open(let repositories, let stores) = app.state else {
            throw FixtureFailure.storeDidNotOpen(String(describing: app.state))
        }
        dependencies = stores

        let now = Date.now
        let exercise = Exercise(
            id: UUID(),
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            name: "Back Squat",
            ukrainianName: nil,
            movement: .squat,
            parentExerciseID: nil,
            equipment: .barbell,
            laterality: .bilateral,
            barType: .standard,
            implementCount: 1,
            isCustom: false,
            isArchived: false,
            notes: ""
        )
        try await repositories.exercises.save(exercise)

        await stores.activeSession.start(on: now)
        await stores.activeSession.addExercise(id: exercise.id)
        await stores.activeSession.loadExercises()
    }

    /// What can go wrong before a screen is ever hosted.
    enum FixtureFailure: Error {
        /// The in-memory store did not open, and this is why.
        case storeDidNotOpen(String)
    }
}

/// The `Logging` module's own copy, read from the resource bundle the app ships.
///
/// **Not a literal, and not `LoggingStrings`.** That type is `internal` to `Logging`, so a test
/// outside it cannot name the key's constant; a literal "Log" copied here would be a second home
/// for a string whose home is the `.strings` file, and would break on a copy change that broke
/// nothing. Reading the shipped bundle also proves the bundle shipped — a resource that failed to
/// copy renders a key where a word should be, which is invisible to every other gate here.
enum LoggingCopy {
    /// One string from `Logging`'s bundle.
    ///
    /// - Parameter key: The key as `LoggingStrings` spells it.
    /// - Returns: The English copy.
    static func string(forKey key: String) -> String {
        guard
            let url = Bundle.main.url(forResource: "Logging_Logging", withExtension: "bundle"),
            let bundle = Bundle(url: url)
        else {
            // A failure here is the resource-bundle trap CLAUDE.md records for `SeedContent`, and
            // it must not read as "the control was not found".
            preconditionFailure("Logging_Logging.bundle is not in the app bundle")
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}
