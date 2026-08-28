import Foundation

/// What the Health-access screen knows (`FR-1.10.4`).
///
/// **A screen's state rather than one of `TR-1.2`'s stores**, on ``BodyweightLogState``'s rule: it
/// is read from this screen alone and lives exactly as long as it does.
///
/// **There is no failed phase.** The one read here answers
/// ``BodyweightSourceAuthorization/unknown`` where it cannot say, so a failure is already a value
/// the screen draws rather than a second axis it has to carry.
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

    /// The source whose authorization this reports, or `nil` where this build has none.
    @ObservationIgnored private let health: (any BodyweightSampleSource)?

    /// Builds the state over the source it reports on.
    ///
    /// - Parameter health: `FR-1.8.2`'s sample source. `nil` reads as a device with no Health,
    ///   which is the same thing to a person looking at this screen.
    init(health: (any BodyweightSampleSource)?) {
        self.health = health
    }

    /// Asks the source how far the request has got. **Prompts nothing** — see
    /// ``BodyweightSampleSource/authorizationState()``, which is why opening this screen is not
    /// first use of the feature (`TR-1.9`).
    func load() async {
        guard phase != .loading else { return }
        phase = .loading
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
