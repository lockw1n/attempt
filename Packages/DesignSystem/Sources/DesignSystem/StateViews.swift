import DesignTokens
import SwiftUI

// Each of the five configures ``StateScaffold`` and renders nothing else, and each exposes the
// scaffold it built. That is what makes the choices testable without a rendering harness: a test
// asks which kind a view chose and which copy it resolved, and a snapshot is left to answer what
// the result looks like.

/// Nothing here yet (`FR-1.13.1`).
///
/// The headline is the caller's, because what is missing is the screen's knowledge — "No exercises
/// yet" is not a sentence this module can write. The action is what turns a dead end into the next
/// tap, and `FR-1.13.2` makes it mandatory on first launch rather than optional.
public struct EmptyStateView: View {
    private let symbolName: String?
    private let headline: Text
    private let message: Text?
    private let action: StateAction?

    /// Builds the state.
    ///
    /// - Parameters:
    ///   - symbolName: An SF Symbol naming what is missing. Defaults to the generic tray — pass a
    ///     screen's own where one reads better.
    ///   - headline: What there is none of, in the caller's words.
    ///   - message: One line on how to get some, where the headline does not already say it.
    ///   - action: The way to create the first one.
    public init(
        symbolName: String? = nil,
        headline: Text,
        message: Text? = nil,
        action: StateAction? = nil
    ) {
        self.symbolName = symbolName
        self.headline = headline
        self.message = message
        self.action = action
    }

    /// The scaffold this view configures.
    var scaffold: StateScaffold {
        StateScaffold(
            kind: .empty,
            symbolName: symbolName,
            headline: headline,
            message: message,
            action: action
        )
    }

    /// The scaffold, as the empty kind.
    public var body: some View { scaffold }
}

/// A read is in flight (`FR-1.13.1`).
///
/// **Most Phase 1 reads never show this.** `G-2.2`/`G-2.3` make the local store synchronous, so a
/// screen that renders this on every appearance is a screen that made a synchronous read
/// asynchronous for nothing. It is for the reads that genuinely wait — HealthKit, a remote fetch.
public struct LoadingStateView: View {
    private let message: Text?

    /// Builds the state.
    ///
    /// - Parameter message: What is being waited for, where the wait is long enough that a bare
    ///   spinner would not say. Omit it for a short one.
    public init(message: Text? = nil) {
        self.message = message
    }

    /// The scaffold this view configures.
    var scaffold: StateScaffold {
        StateScaffold(kind: .loading, message: message)
    }

    /// The scaffold, as the loading kind.
    public var body: some View { scaffold }
}

/// Something failed (`FR-1.13.1`).
///
/// **A retry is offered only where retrying could work.** A button that re-runs a read that will
/// fail again the same way is worse than no button, so the handler is optional and the caller
/// decides — the same judgement `SettingsLandingView` makes when it keeps its controls visible
/// beside a failed write.
public struct ErrorStateView: View {
    private let headline: Text?
    private let message: Text
    private let retry: (() -> Void)?

    /// Builds the state.
    ///
    /// - Parameters:
    ///   - headline: What failed, in the screen's words. Omit it for this module's generic heading.
    ///   - message: What the user can understand about the failure — not a diagnostic string.
    ///   - retry: What to run again, where running it again could succeed.
    public init(headline: Text? = nil, message: Text, retry: (() -> Void)? = nil) {
        self.headline = headline
        self.message = message
        self.retry = retry
    }

    /// The scaffold this view configures. The fallback heading is the kind's.
    var scaffold: StateScaffold {
        StateScaffold(
            kind: .error,
            headline: headline,
            message: message,
            action: retry.map { handler in
                StateAction(Text(DesignSystemStrings.retry), handler: handler)
            }
        )
    }

    /// The scaffold, as the error kind.
    public var body: some View { scaffold }
}

/// Nothing local to show, and no connection to fetch it with (`FR-1.13.1`).
///
/// **Not an error, and not a blocked action.** `G-2.1` makes every action in this app work offline,
/// so a screen reaching for this because a *write* could not reach the network has misread its own
/// requirement. This is for the rare surface whose content is remote and not yet cached.
///
/// It carries no caller copy at all: being offline means the same thing on every screen, and a
/// screen that wanted to say it differently would be saying something else. Both strings are the
/// kind's, which is why this view passes none.
public struct OfflineStateView: View {
    private let retry: (() -> Void)?

    /// Builds the state.
    ///
    /// - Parameter retry: What to fetch again once a connection is back.
    public init(retry: (() -> Void)? = nil) {
        self.retry = retry
    }

    /// The scaffold this view configures. Both the heading and the message are the kind's.
    var scaffold: StateScaffold {
        StateScaffold(
            kind: .offline,
            action: retry.map { handler in
                StateAction(Text(DesignSystemStrings.retry), handler: handler)
            }
        )
    }

    /// The scaffold, as the offline kind.
    public var body: some View { scaffold }
}

/// A derived value or chart has data and not enough of it (`FR-1.13.3`).
///
/// **The message is required, and it has to name what would be enough.** "Log two more sets to see
/// a trend" is the whole point of the requirement — a chart-shaped blank, or a zero, is what this
/// state exists to replace. The obligation is on the caller because only the caller knows the
/// threshold it fell short of.
///
/// This is also the component the silent refusals get explained through: a 12-rep set, assisted
/// work, a failed set and a training max that cannot be derived are all *this* state rather than an
/// omission, and the copy that says so is owed by the screens that show them.
public struct InsufficientDataView: View {
    private let headline: Text?
    private let message: Text

    /// Builds the state.
    ///
    /// - Parameters:
    ///   - headline: What cannot be shown. Omit it for this module's generic heading.
    ///   - message: What would make it showable, stated concretely.
    public init(headline: Text? = nil, message: Text) {
        self.headline = headline
        self.message = message
    }

    /// The scaffold this view configures. The fallback heading is the kind's.
    var scaffold: StateScaffold {
        StateScaffold(kind: .insufficientData, headline: headline, message: message)
    }

    /// The scaffold, as the insufficient-data kind.
    public var body: some View { scaffold }
}
