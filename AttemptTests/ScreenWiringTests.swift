import Foundation
import Logging
import PowerliftingCore
import RepositoryInterface
import SwiftUI
import Testing

@testable import Attempt

/// That a screen's parts are still wired to the screen (`FR-1.2.3`, `G-6.3`).
///
/// **Not `TR-1.12` and not `DOD-17.6`.** `TR-1.12` is the snapshot requirement, T-1.08's, and this
/// suite exists for what a snapshot reference cannot see — keying it there would tick the one claim
/// it argues against making. `DOD-17.6`'s literal reading wants an XCUITest, which T-1.94 declined
/// to build; the requirement is met by a `DayStore` walk plus a simulator pass and is not advanced
/// here. What is advanced is `FR-1.2.3`: that the control which adds a set still reaches the editor
/// that takes one.
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
/// script says extraction reads the built module, so a link in a `private` or `internal` member's
/// doc comment is not in the graph and is never checked, whatever `--minimum-access-level` says.
/// Here: activation reads the accessibility tree, so **a control that publishes no accessibility
/// element is not in the tree and is never checked, whatever the screen draws** — and neither is a
/// control that is in the tree but covered, mis-sized, or behind a gesture that wins. This proves
/// that a screen's parts are still wired to the screen, never that they can be touched.
///
/// **Serialized, because the scene is shared and there is only one.** ``HostedScreen`` puts its
/// window on the app's own `UIWindowScene` and makes it key; two tests suspending in `settle()`
/// interleave whatever the actor, so a second window would take key from the first mid-test and a
/// presentation raised from a controller whose window is no longer key can quietly fail to appear.
/// Same argument as ``LaunchSequenceTests``' one layer down, over a different piece of
/// process-global state.
@MainActor
@Suite("Screen wiring (FR-1.2.3)", .serialized)
struct ScreenWiringTests {
    /// Tapping a card's Log control raises the set editor over the workout.
    ///
    /// **The stores come from the app's own composition root; the call does not.** `AppDependencies`
    /// builds every store the screen is handed, so none of them is a hand-assembled stand-in —
    /// T-16.17's finding, that a fixture assembling a shared component's parts is a second place the
    /// screen's decision lives. But `RootTabView.activeSessionRoot` is `private`, so the three
    /// arguments below are still a *copy* of the call it makes, and a screen that gained a fourth
    /// argument there would leave this fixture compiling against the old shape of the same screen.
    /// The copy is one line long and reviewable; the claim it supports is about the modifiers on the
    /// screen rather than about the arguments to it, which is why the copy is tolerable here.
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

        let label = try LoggingCopy.string(forKey: "logging.session.set.add.action")
        // Named per case rather than as a `Bool`: "not in the tree" is a screen that did not draw
        // the control, "refused" is a screen that drew it inert, and a message asserting the first
        // over the second sends the next reader looking in the wrong place.
        switch screen.activate(label: label) {
        case .activated:
            break
        case .notFound:
            Issue.record(
                """
                no activatable element labelled "\(label)". \
                What the screen published: \(screen.activatableLabels())
                """)
        case .refused:
            Issue.record(
                """
                the element labelled "\(label)" is in the tree and declined to activate — \
                the screen drew the control disabled or inert, it is not missing.
                """)
        }
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
    ///
    /// **It cannot fail on its own, and that is not what it is for.** Every claim here is implied by
    /// the test above — a named control that activates is a non-empty tree with a control in it — so
    /// no defect reddens this one alone. What it buys is the *reading*: when both go red the tree
    /// was never published, and when only the first does the tree was published and the wiring was
    /// gone. `T-1.82` inherits the second of those as its starting point.
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
///
/// **That last claim needs the key-level check below to be true at all**, and it is the reason this
/// type is more than one line. `localizedString(forKey:value:table:)` answers with **the key
/// itself** when the key is missing and `value` is empty — and `LoggingStrings` resolves against
/// this same bundle, so the screen would draw the key too. Both sides then agree on
/// `"logging.session.set.add.action"`, the label matches, and a `.strings` file that never shipped
/// passes as a screen that works. Two lookups agreeing on the same wrong answer is `T-16.07`'s
/// family, one layer out from the store: the `preconditionFailure` catches a missing *bundle*, and
/// only the comparison against `key` catches a missing *key*.
enum LoggingCopy {
    /// What can be wrong with the copy before a screen is ever asked about it.
    ///
    /// **Thrown rather than a `preconditionFailure`**, which is what this was first written as: a
    /// trap kills the process and takes every other suite's result with it, and a resource fault is
    /// exactly the failure that most needs the rest of the run to still report. One test goes red,
    /// and its message says the resource rather than the screen.
    enum CopyFailure: Error, CustomStringConvertible {
        /// The whole resource bundle is missing from the app — CLAUDE.md's `SeedContent` trap.
        case bundleMissing

        /// The bundle is there and holds no copy for this key.
        case keyMissing(String)

        /// What went wrong, and where to look.
        var description: String {
            switch self {
            case .bundleMissing:
                "Logging_Logging.bundle is not in the app bundle — the resource did not copy."
            case .keyMissing(let key):
                """
                Logging_Logging.bundle has no copy for "\(key)": the lookup answered with the key. \
                The bundle shipped and the string did not — a renamed key, or an en.lproj that \
                failed to copy. The screen draws the key too, so this must not read as a control \
                that was not found.
                """
            }
        }
    }

    /// One string from `Logging`'s bundle.
    ///
    /// - Parameter key: The key as `LoggingStrings` spells it.
    /// - Returns: The English copy, which is never the key.
    /// - Throws: ``CopyFailure`` if the bundle or the key is missing.
    static func string(forKey key: String) throws -> String {
        guard
            let url = Bundle.main.url(forResource: "Logging_Logging", withExtension: "bundle"),
            let bundle = Bundle(url: url)
        else {
            throw CopyFailure.bundleMissing
        }
        let copy = bundle.localizedString(forKey: key, value: nil, table: nil)
        guard copy != key else { throw CopyFailure.keyMissing(key) }
        return copy
    }
}
