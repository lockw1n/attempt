import Foundation

/// What the Health-access screen knows (`FR-1.10.4`).
///
/// **A screen's state rather than one of `TR-1.2`'s stores**, on ``BodyweightLogState``'s rule: it
/// is read from this screen alone and lives exactly as long as it does.
///
/// **There is no failed phase.** The one read here answers
/// ``BodyweightSourceAuthorization/unknown`` where it cannot say, so a failure is already a value
/// the screen draws rather than a second axis it has to carry.
///
/// **Two entry points, one read.** ``load()`` is the first look and draws the wait; ``refresh()``
/// is every later one and never does. Both are single-flight.
@Observable
final class HealthAccessState {
    /// What the screen has to show.
    enum Phase: Equatable {
        /// Nothing has been read yet.
        case idle

        /// The read is in flight. It is a real wait — the source is out of process.
        case loading

        /// How far authorization has got, as much of it as the source would say.
        case loaded(BodyweightSourceAuthorization)
    }

    /// The screen's read state.
    private(set) var phase: Phase = .idle

    /// Whether a read is in flight.
    ///
    /// **Not the phase, which is why it exists.** A refresh keeps the status that is drawn, so
    /// `loading` stops being the thing that says a read is running and cannot be what makes these
    /// calls single-flight.
    @ObservationIgnored private var isReading = false

    /// The source whose authorization this reports, or `nil` where this build has none.
    @ObservationIgnored private let health: (any BodyweightSampleSource)?

    /// Builds the state over the source it reports on.
    ///
    /// - Parameter health: `FR-1.8.2`'s sample source. `nil` reads as a device with no Health,
    ///   which is the same thing to a person looking at this screen.
    init(health: (any BodyweightSampleSource)?) {
        self.health = health
    }

    /// The first look: asks the source how far the request has got, drawing the wait while it does.
    ///
    /// **Prompts nothing** — see ``BodyweightSampleSource/authorizationState()``, which is why
    /// opening this screen is not first use of the feature (`TR-1.9`).
    func load() async {
        guard !isReading else { return }
        isReading = true
        defer { isReading = false }
        phase = .loading
        await read()
    }

    /// Reads again after the screen has been away, keeping what is already drawn.
    ///
    /// **The status moves without this screen being rebuilt**, which is the whole of why this
    /// exists: the prompt is raised by the import this screen links to (`TR-1.9`), which comes back
    /// by a pop, and the switch itself is thrown in another app, which comes back by a foreground.
    /// Neither rebuilds the view, and a `.task` runs once per view identity — so one read would
    /// leave the screen reporting what was true when it opened.
    ///
    /// **It draws no wait**, unlike ``load()``: a reappearance that changes nothing would otherwise
    /// flash a spinner over a status that was already right.
    ///
    /// **It does nothing before the first read has landed.** The view's `onAppear` fires beside its
    /// `task` on the way in, and a refresh racing that first read is a second status read for
    /// nothing.
    func refresh() async {
        guard case .loaded = phase, !isReading else { return }
        isReading = true
        defer { isReading = false }
        await read()
    }

    /// The read both entry points share. It is the caller that decides what is drawn while it runs.
    private func read() async {
        guard let health else {
            phase = .loaded(.unavailable)
            return
        }
        phase = .loaded(await health.authorizationState())
    }
}

/// Which of the screen's states to draw — ``HealthAccessState/Phase`` with the wait folded in.
///
/// The same split ``BodyweightLogScreenState`` makes, and for the same reason: a reference can be
/// rendered over one of these without a source behind it.
enum HealthAccessScreenState: Equatable, CaseIterable {
    /// The source has not answered yet.
    case loading

    /// This device has no health source, so there is no permission to hold.
    case unavailable

    /// The prompt has never been raised.
    case notAsked

    /// The prompt has been raised and answered. **Not "granted"** — nothing here can say that.
    case answered

    /// The source would not say.
    case unknown

    /// Which state a phase is.
    ///
    /// - Parameter phase: The screen's read state.
    /// - Returns: The state to draw.
    static func current(_ phase: HealthAccessState.Phase) -> Self {
        switch phase {
        case .idle, .loading: .loading
        case .loaded(.unavailable): .unavailable
        case .loaded(.notAsked): .notAsked
        case .loaded(.answered): .answered
        case .loaded(.unknown): .unknown
        }
    }
}
