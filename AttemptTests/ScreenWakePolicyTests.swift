import Foundation
import Logging
import Persistence
import RepositoryInterface
import Testing

@testable import Attempt

/// What the shell does with the idle timer (`NFR-1.9`).
///
/// **The gap this exists for, and it is one word wide.** `NFR-1.9` has two halves and each is
/// tested where it lives — `ScreenWakePreference` owns the toggle and `ActiveSessionStore` owns
/// whether a workout is in progress — but which *reading* of the store the shell passes to the
/// preference is neither's, and it is the whole of the defect `T-1.84` measured on a phone: a
/// planned day that has ended keeps its row held so the checklist can draw it, so
/// ``Logging/ActiveSessionStore/isActive`` stays `true` long after the lifter has stopped lifting
/// and the shell held the screen on every tab until the app backgrounded. Put `isActive` back on
/// that line and every package suite stays green; this is what fails.
///
/// **Held-and-ended is reached the way History reaches it, not the way a day does.** `endDay()` is
/// `internal` to `Logging`, so this target cannot call it — but the state it leaves is a finished
/// row that the store holds, which ``Logging/ActiveSessionStore/adopt(sessionID:)`` produces
/// exactly. The claim is about the state, so the route to it does not matter.
///
/// **Serialized, and it moves a real preference**, for ``LaunchSequenceTests``' reason: opening a
/// `.file` store with the shipped sync default in force would mirror the fixture into the signed-in
/// iCloud account.
@MainActor
@Suite("The shell's idle-timer policy (NFR-1.9)", .serialized)
struct ScreenWakePolicyTests {
    @Test("The screen is held while a workout runs, and released when it ends — held row or not")
    func theScreenFollowsTheWorkoutAndNotTheHeldRow() async throws {
        let guarded = SyncPreferenceGuard()
        defer { guarded.restore() }
        let url = TemporaryStore.makeURL()
        defer { TemporaryStore.remove(at: url) }

        let dependencies = AppDependencies(location: .file(url))
        guard case .open(_, let stores) = dependencies.state else {
            Issue.record("the store did not open: \(dependencies.state)")
            return
        }
        // Pinned rather than inherited: `UserSettings.defaultKeepScreenAwake` is this test's other
        // half, and a test of the session half must not be able to pass because that one flipped.
        stores.screenWake.adopt(true)

        // No workout at all — the exercise library's situation, and `FR-17.9.5`'s unanswered day.
        #expect(!ScreenWakePolicy.keepsScreenAwake(in: dependencies.state))

        await stores.activeSession.start(on: .now)
        let started = try #require(stores.activeSession.session?.id)
        #expect(ScreenWakePolicy.keepsScreenAwake(in: dependencies.state))

        // The free workout's end, which releases the row as well as the screen.
        await stores.activeSession.finish()
        #expect(!stores.activeSession.isActive)
        #expect(!ScreenWakePolicy.keepsScreenAwake(in: dependencies.state))

        // And the planned day's end, which does not. This is the assertion that fails if the line
        // goes back to reading `isActive`.
        await stores.activeSession.adopt(sessionID: started)
        #expect(stores.activeSession.isActive)
        #expect(!ScreenWakePolicy.keepsScreenAwake(in: dependencies.state))
    }

    @Test("The preference alone holds nothing, whatever the workout is doing")
    func thePreferenceIsTheOtherHalf() async throws {
        let guarded = SyncPreferenceGuard()
        defer { guarded.restore() }
        let url = TemporaryStore.makeURL()
        defer { TemporaryStore.remove(at: url) }

        let dependencies = AppDependencies(location: .file(url))
        guard case .open(_, let stores) = dependencies.state else {
            Issue.record("the store did not open: \(dependencies.state)")
            return
        }

        await stores.activeSession.start(on: .now)
        stores.screenWake.adopt(false)

        // A workout in progress and the toggle off is the case `NFR-1.9` gives the user, and the
        // one a shell reading the session alone would get wrong.
        #expect(stores.activeSession.isInProgress)
        #expect(!ScreenWakePolicy.keepsScreenAwake(in: dependencies.state))
    }
}
