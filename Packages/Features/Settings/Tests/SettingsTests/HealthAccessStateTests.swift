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
        await Task.yield()
        async let second: Void = state.load()
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
        await Task.yield()
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
@MainActor
private final class GatedAuthorizationSource: BodyweightSampleSource {
    /// How many status reads have reached the source.
    private(set) var statusReads = 0

    private var waiting: [CheckedContinuation<Void, Never>] = []

    private var isReleased = false

    let isAvailable = true

    func authorize() async {}

    func samples() async -> [BodyweightSample] { [] }

    func authorizationState() async -> BodyweightSourceAuthorization {
        statusReads += 1
        if !isReleased {
            await withCheckedContinuation { waiting.append($0) }
        }
        return .answered
    }

    /// Closes the gate again, so a later read suspends the way the first one did.
    func hold() {
        isReleased = false
    }

    /// Lets every suspended read finish, and every later one through.
    func release() {
        isReleased = true
        let waiters = waiting
        waiting.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
