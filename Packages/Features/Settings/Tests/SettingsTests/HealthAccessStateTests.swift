import Foundation
import Testing

@testable import Settings

/// `FR-1.10.4`: what the screen may say about Health access, and — mostly — what it may not.
@MainActor
@Suite("Health access")
struct HealthAccessStateTests {
    @Test("Nothing is claimed before the source has answered")
    func startsUnread() {
        let state = HealthAccessState(health: AuthorizationSource(answer: .answered))
        #expect(state.phase == .idle)
        // The wait is what the screen draws, and `idle` must fold into it rather than into a status
        // nobody asked for yet.
        #expect(HealthAccessScreenState.current(state.phase) == .loading)
    }

    @Test(
        "Every answer a source can give reaches the screen unchanged",
        arguments: [
            (BodyweightSourceAuthorization.unavailable, HealthAccessScreenState.unavailable),
            (.notAsked, .notAsked),
            (.answered, .answered),
            (.unknown, .unknown),
        ])
    func everyAnswerIsCarried(
        answer: BodyweightSourceAuthorization, drawn: HealthAccessScreenState
    ) async {
        let state = HealthAccessState(health: AuthorizationSource(answer: answer))
        await state.load()
        #expect(state.phase == .loaded(answer))
        #expect(HealthAccessScreenState.current(state.phase) == drawn)
    }

    @Test("A build with no source at all reads as a device with no Health")
    func noSourceIsUnavailable() async {
        let state = HealthAccessState(health: nil)
        await state.load()
        // Anchored to the literal, not to another optional: `nil == nil` would pass this without
        // the state having decided anything.
        #expect(state.phase == .loaded(.unavailable))
    }

    @Test("Reading the status raises no prompt")
    func statusDoesNotPrompt() async {
        // TR-1.9 owes the prompt to first use of the import. A settings screen that asked for the
        // status by asking for authorization would move it to whenever the screen was opened, and
        // the compiler cannot notice that — only a count can.
        let source = AuthorizationSource(answer: .notAsked)
        let state = HealthAccessState(health: source)
        await state.load()
        #expect(source.authorizations == 0)
        #expect(source.statusReads == 1)
    }

    @Test("A second read while one is in flight does not start a second")
    func loadIsNotReentrant() async {
        let source = GatedAuthorizationSource()
        let state = HealthAccessState(health: source)
        // BOTH CALLS ARE DETACHED FROM THIS BODY ON PURPOSE. Awaiting the second one here would
        // deadlock the test rather than fail it if the guard were removed — measured: the probe
        // hung for two minutes instead of reporting the count. A hang is not an assertion.
        async let first: Void = state.load()
        // The rendezvous, not a yield: the second call has to be issued while the first is provably
        // standing inside the gate, which is the whole claim in this test's name. A `Task.yield()`
        // stood here and promised none of that — see ``GatedAuthorizationSource/arrival()``.
        await source.arrival()
        async let second: Void = state.load()
        // THIS ONE STAYS A YIELD, because a refused call reaches nothing and so can be waited on by
        // nothing. It is the weaker half of this test: were the second call left unscheduled until
        // after `release()` had let the first one finish, it would read the open gate and the count
        // below would be 2. The window is narrow — the guard is held across everything between —
        // and it survived 100 package runs, 40 of them under eight-way CPU contention.
        await Task.yield()
        source.release()
        _ = await (first, second)
        #expect(source.statusReads == 1)
        #expect(state.phase == .loaded(.answered))
    }

    @Test("Health's own root is the destination, spelled exactly")
    func destinationIsTheHealthApp() throws {
        // A URL that does not parse opens nothing and the button would fail silently, which is the
        // one failure this screen was written to avoid. The scheme is Health's own; the app's page
        // under Settings is deliberately NOT the fallback — measured, the read switches are not on
        // it.
        let url = try #require(HealthAccessView.healthApp)
        #expect(url.absoluteString == "x-apple-health://")
    }

    @Test("A refresh before the first read has landed does nothing")
    func refreshWaitsForTheFirstRead() async {
        // `onAppear` fires beside `task` on the way in, so this runs on every entry to the screen.
        // A refresh that read here would be a second status read for nothing, racing the first.
        let source = AuthorizationSource(answer: .notAsked)
        let state = HealthAccessState(health: source)
        await state.refresh()
        #expect(source.statusReads == 0)
        #expect(state.phase == .idle)
    }

    @Test("A status that moved while the screen was away is picked up on the way back")
    func refreshCarriesAChangedAnswer() async {
        // The prompt is raised by the import THIS SCREEN LINKS TO, and coming back from it is a
        // pop rather than a rebuild — so a screen that read once would still say "not requested"
        // after the person did exactly what it told them to.
        let source = AuthorizationSource(answer: .notAsked)
        let state = HealthAccessState(health: source)
        await state.load()
        #expect(state.phase == .loaded(.notAsked))
        source.answer = .answered
        await state.refresh()
        #expect(state.phase == .loaded(.answered))
        #expect(source.statusReads == 2)
    }

    @Test("A refresh never draws the wait over a status already on screen")
    func refreshKeepsWhatIsDrawn() async {
        let source = GatedAuthorizationSource()
        let state = HealthAccessState(health: source)
        // The first read is the one that draws the wait, so let it land before the part under test.
        source.release()
        await state.load()
        #expect(HealthAccessScreenState.current(state.phase) == .answered)

        source.hold()
        async let refreshing: Void = state.refresh()
        // WAIT FOR THE READ, NOT FOR A TURN OF THE SCHEDULER. A `Task.yield()` stood here and is
        // not a barrier: whether the detached refresh had reached the source by the time this task
        // resumed was the cooperative pool's business, and roughly once in thirty package runs it
        // had not — the count below read 1 against a `refresh()` that was working perfectly.
        await source.arrival()
        // THE COUNT IS WHAT MAKES THE ASSERTION BELOW NON-VACUOUS. A refresh that had not yet
        // reached the source would leave the status untouched for the wrong reason, and this test
        // would pass on a `refresh()` that cleared it the moment it ran.
        #expect(source.statusReads == 2)
        #expect(HealthAccessScreenState.current(state.phase) == .answered)
        source.release()
        await refreshing
        #expect(state.phase == .loaded(.answered))
    }

    @Test("No status a source can report claims access was granted")
    func nothingClaimsAGrant() {
        // The type is the guard: a `granted` case added later would be a sentence the app cannot
        // know is true, and this is where that lands.
        let names = BodyweightSourceAuthorization.allCases.map(String.init(describing:))
        #expect(names == ["unavailable", "notAsked", "answered", "unknown"])
    }
}

// MARK: - Fixtures

/// A source that answers one fixed status, counting what was asked of it.
@MainActor
private final class AuthorizationSource: BodyweightSampleSource {
    /// What the source says next. A `var`, because the whole point of a refresh is that this moves
    /// while the screen is alive.
    var answer: BodyweightSourceAuthorization

    /// How many times the prompt was asked for. This screen must never move it.
    private(set) var authorizations = 0

    /// How many times the status was read.
    private(set) var statusReads = 0

    let isAvailable = true

    init(answer: BodyweightSourceAuthorization) {
        self.answer = answer
    }

    func authorize() async {
        authorizations += 1
    }

    func samples() async -> [BodyweightSample] { [] }

    func authorizationState() async -> BodyweightSourceAuthorization {
        statusReads += 1
        return answer
    }
}

/// A source whose status read suspends until it is released, so a second `load()` really does
/// arrive while the first is still in flight.
///
/// **``arrival()`` is what makes the concurrency cases deterministic rather than timing-dependent**,
/// the same rendezvous `History`'s and `Logging`'s `GatedWorkoutRepository` carry and for the same
/// reason: it returns once a read has reached the source, so a test knows where the other task is
/// standing instead of guessing at the scheduler.
///
/// **A `@MainActor` class rather than an `actor`**, which is where those two differ from this one.
/// They conform to `RepositoryInterface` protocols, whose package is `.defaultIsolation(nil)` and
/// whose protocols refine `Sendable`, so `G-6.4` leaves them no other shape. ``BodyweightSampleSource``
/// is declared in this module, under `.defaultIsolation(MainActor.self)` and refining nothing — its
/// requirements are main-actor isolated, an `actor` could satisfy them only through the isolated
/// conformance `G-6.4` refuses, and the state below is touched on the main actor alone anyway.
@MainActor
private final class GatedAuthorizationSource: BodyweightSampleSource {
    /// How many status reads have reached the source.
    private(set) var statusReads = 0

    private var waiting: [CheckedContinuation<Void, Never>] = []

    private var isReleased = false

    /// Whether a read has reached the source since the gate was last closed.
    private var hasArrived = false

    private var arrived: CheckedContinuation<Void, Never>?

    let isAvailable = true

    func authorize() async {}

    func samples() async -> [BodyweightSample] { [] }

    func authorizationState() async -> BodyweightSourceAuthorization {
        statusReads += 1
        hasArrived = true
        arrived?.resume()
        arrived = nil
        if !isReleased {
            await withCheckedContinuation { waiting.append($0) }
        }
        return .answered
    }

    /// Suspends until a status read has reached the source since the gate was last closed.
    ///
    /// **This is the barrier `Task.yield()` is not.** Yielding reschedules the calling task; it
    /// promises nothing about a read issued in another one having got anywhere, and under load it
    /// had not — measured at two failures in sixty package runs on the count in
    /// ``HealthAccessStateTests/refreshKeepsWhatIsDrawn()`` before this existed.
    ///
    /// **With the gate closed it also says where that read is standing.** Nothing suspends between
    /// the count above and the gate below, so a caller resumed from here knows the read is inside
    /// the gate rather than merely past the door.
    func arrival() async {
        guard !hasArrived else { return }
        await withCheckedContinuation { arrived = $0 }
    }

    /// Closes the gate again, so a later read suspends the way the first one did.
    ///
    /// **It reopens the rendezvous too**: an ``arrival()`` after this waits for a read of its own
    /// rather than being answered instantly by one from the round before.
    func hold() {
        isReleased = false
        hasArrived = false
    }

    /// Lets every suspended read finish, and every later one through.
    func release() {
        isReleased = true
        let waiters = waiting
        waiting.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
