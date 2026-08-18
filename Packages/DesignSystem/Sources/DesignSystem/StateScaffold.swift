import DesignTokens
import SwiftUI

/// Which of `FR-1.13.1`'s states — plus `FR-1.13.3`'s — a placeholder is reporting.
///
/// The kind exists so the glyph, the tint and the copy a state does *not* take from its caller are
/// a choice among tokens and catalogue keys rather than something each of the five views writes for
/// itself. That is the layer a test can reach: what a state renders is a snapshot's question, but
/// which constant it chose is a unit test's.
///
/// **Empty and insufficient-data are deliberately not the same case even though they draw alike.**
/// One says there is nothing here yet; the other says there is something here and it is not enough
/// to compute from — `FR-1.13.3` exists because rendering the second as the first is what produces
/// a zero or a blank chart.
nonisolated enum StateKind: Sendable, CaseIterable {
    /// Nothing has been created yet (`FR-1.13.1`).
    case empty

    /// A read is in flight. Rare here: `G-2.2`/`G-2.3` make Phase 1's reads local and synchronous,
    /// so this is for the few that are not.
    case loading

    /// Something failed, and the user may be able to do something about it.
    case error

    /// Nothing local to show and no connection to fetch it with (`G-2.1`) — not a blocked action.
    case offline

    /// A derived value or chart has data, and not enough of it (`FR-1.13.3`).
    case insufficientData

    /// What a state draws above its copy, and what VoiceOver is to make of it.
    ///
    /// One value rather than two independent ones, because it is one decision: a spinner has no
    /// text and so needs a label, an SF Symbol announces its own name and so has to be silenced or
    /// it prefixes every state with "exclamation mark triangle" (`G-4.2`). Kept apart, a state
    /// could be given both or neither.
    enum Indicator: Equatable, Sendable {
        /// A progress indicator, announced as `label` because it has nothing else to say.
        case spinner(label: LocalizedStringResource)

        /// An SF Symbol, hidden from VoiceOver because the copy beneath it says the same thing.
        case glyph(String)
    }

    /// This state's indicator.
    ///
    /// Loading names no glyph on purpose: a static symbol standing where a progress indicator
    /// belongs reads as a stalled one.
    var indicator: Indicator {
        switch self {
        case .empty: .glyph("tray")
        case .loading: .spinner(label: DesignSystemStrings.loadingLabel)
        case .error: .glyph("exclamationmark.triangle")
        case .offline: .glyph("wifi.slash")
        case .insufficientData: .glyph("chart.line.uptrend.xyaxis")
        }
    }

    /// The SF Symbol this state draws, or `nil` for the one state that draws a spinner instead.
    var symbolName: String? {
        guard case .glyph(let name) = indicator else { return nil }
        return name
    }

    /// The heading this module supplies when the caller does not, or `nil` where the caller must.
    ///
    /// Empty has none deliberately: what is missing is the screen's knowledge, and "No exercises
    /// yet" is not a sentence this module can write. Loading has none because a spinner is not a
    /// heading.
    var defaultHeadline: LocalizedStringResource? {
        switch self {
        case .empty, .loading: nil
        case .error: DesignSystemStrings.errorHeadline
        case .offline: DesignSystemStrings.offlineHeadline
        case .insufficientData: DesignSystemStrings.insufficientDataHeadline
        }
    }

    /// The message this module owns outright, for the one state whose copy is the same everywhere.
    ///
    /// Being offline means the same thing on every screen, so the caller supplies nothing and
    /// cannot say it differently — a screen that wanted to would be saying something else.
    var fixedMessage: LocalizedStringResource? {
        self == .offline ? DesignSystemStrings.offlineMessage : nil
    }

    /// The colour of this state's glyph or spinner.
    ///
    /// Only ``error`` takes a semantic colour (`G-7.3`): it is the one state the user is being
    /// asked to act on. The glyph differs in every case regardless, so the tint is never the only
    /// cue (`G-4.5`).
    var tint: ColorToken {
        switch self {
        case .empty, .insufficientData: .textTertiary
        case .loading: .brandAccent
        case .error: .negative
        case .offline: .textSecondary
        }
    }
}

/// The one action a state placeholder may offer — "Log your first workout", "Try again".
///
/// A struct rather than two parameters, so a caller cannot pass a label with no handler or a
/// handler with no label.
public struct StateAction {
    let label: Text
    let handler: () -> Void

    /// Builds the action.
    ///
    /// - Parameters:
    ///   - label: The button's title, built by the caller so it is localized in the caller's
    ///     bundle — see ``GroupedSection`` for why.
    ///   - handler: What the button does.
    public init(_ label: Text, handler: @escaping () -> Void) {
        self.label = label
        self.handler = handler
    }
}

/// The layout all five state views share: indicator, copy, at most one action.
///
/// Internal, because the five kinds are the API. A caller reaching for the scaffold directly would
/// be able to build a sixth state, which is the thing `FR-1.13.1` is trying to stop.
///
/// **It claims width but not height.** A screen that wants its empty state centred in the list area
/// says so where it knows how tall that area is; a scaffold that expanded on its own could not sit
/// inside a ``Card``.
struct StateScaffold: View {
    let kind: StateKind
    let symbolName: String?
    let headline: Text?
    let message: Text?
    let action: StateAction?

    init(
        kind: StateKind,
        symbolName: String? = nil,
        headline: Text? = nil,
        message: Text? = nil,
        action: StateAction? = nil
    ) {
        self.kind = kind
        self.symbolName = symbolName
        self.headline = headline
        self.message = message
        self.action = action
    }

    /// The heading actually shown: the caller's where it gave one, otherwise the kind's fallback.
    var resolvedHeadline: Text? {
        headline ?? kind.defaultHeadline.map { Text($0) }
    }

    /// The message actually shown.
    ///
    /// The kind's own copy outranks the caller's, because the only kind that has any is the one
    /// whose message is not the caller's to write.
    var resolvedMessage: Text? {
        if let fixed = kind.fixedMessage { return Text(fixed) }
        return message
    }

    /// What the spinner announces, or `nil` when the copy beneath it already says it.
    ///
    /// A loading state carrying a message would otherwise be two VoiceOver stops — "Loading", then
    /// the message — where the requirement is one coherent sentence (`G-4.2`). The message is the
    /// more useful of the two, so it speaks and the spinner falls silent.
    var spinnerAnnouncement: LocalizedStringResource? {
        guard case .spinner(let label) = kind.indicator else { return nil }
        return resolvedMessage == nil ? label : nil
    }

    var body: some View {
        VStack(spacing: Spacing.lg.points) {
            indicator
            if resolvedHeadline != nil || resolvedMessage != nil {
                copy
            }
            if let action {
                Button(action: action.handler) { action.label }
                    .buttonStyle(.primaryAction)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.xl.points)
    }

    /// The spinner, or the glyph.
    @ViewBuilder private var indicator: some View {
        switch kind.indicator {
        case .spinner(let label):
            ProgressView()
                .tint(kind.tint)
                .accessibilityLabel(Text(label))
                .accessibilityHidden(spinnerAnnouncement == nil)
        case .glyph(let name):
            Image(systemName: symbolName ?? name)
                .font(Typography.screenTitle.font)
                .foregroundStyle(kind.tint)
                .accessibilityHidden(true)
        }
    }

    /// Headline and message as one VoiceOver element, so the state reads as a sentence rather than
    /// as two stops (`G-4.2`). The action stays a separate element — combining it would make the
    /// button unreachable.
    @ViewBuilder private var copy: some View {
        VStack(spacing: Spacing.sm.points) {
            if let resolvedHeadline {
                resolvedHeadline
                    .font(Typography.cardTitle.font)
                    .foregroundStyle(ColorToken.textPrimary)
            }
            if let resolvedMessage {
                resolvedMessage
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}
