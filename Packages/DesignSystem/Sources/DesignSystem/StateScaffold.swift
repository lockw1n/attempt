import DesignTokens
import SwiftUI

/// Which of `FR-1.13.1`'s states — plus `FR-1.13.3`'s — a placeholder is reporting.
///
/// The kind exists so the glyph and the tint are a *choice among tokens* rather than something each
/// of the five views writes for itself, which is the layer a test can hold.
///
/// **Empty and insufficient-data are deliberately not the same case even though they draw alike.**
/// One says there is nothing here yet; the other says there is something here and it is not enough
/// to compute from — `FR-1.13.3` exists because rendering the second as the first is what produces
/// a zero or a blank chart.
public nonisolated enum StateKind: Sendable, CaseIterable {
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

    /// The SF Symbol this state draws above its copy, or `nil` for the one state that draws a
    /// spinner instead.
    ///
    /// Loading names none on purpose: a static glyph where a progress indicator belongs reads as a
    /// stalled one.
    public var symbolName: String? {
        switch self {
        case .empty: "tray"
        case .loading: nil
        case .error: "exclamationmark.triangle"
        case .offline: "wifi.slash"
        case .insufficientData: "chart.line.uptrend.xyaxis"
        }
    }

    /// The colour of this state's glyph or spinner.
    ///
    /// Only ``error`` takes a semantic colour (`G-7.3`): it is the one state the user is being
    /// asked to act on. The glyph differs in every case regardless, so the tint is never the only
    /// cue (`G-4.5`).
    public var tint: ColorToken {
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

    var body: some View {
        VStack(spacing: Spacing.lg.points) {
            indicator
            if headline != nil || message != nil {
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
    ///
    /// The glyph is hidden from VoiceOver: an SF Symbol announces its own name, so leaving it
    /// visible prefixes every state with "exclamation mark triangle" (`G-4.2`). The spinner is the
    /// opposite case — it has nothing to announce, so it is given the one string it needs.
    @ViewBuilder private var indicator: some View {
        if kind == .loading {
            ProgressView()
                .tint(kind.tint)
                .accessibilityLabel(Text(DesignSystemStrings.loadingLabel))
        } else if let name = symbolName ?? kind.symbolName {
            Image(systemName: name)
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
            if let headline {
                headline
                    .font(Typography.cardTitle.font)
                    .foregroundStyle(ColorToken.textPrimary)
            }
            if let message {
                message
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}
