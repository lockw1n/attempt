import DesignTokens
import SwiftUI

/// Which way a value moved (`G-7.3`).
///
/// **Every direction carries three independent cues, and only one of them is colour.** `G-4.5`
/// forbids information conveyed by colour alone, so the glyph and the sign character are not
/// decoration on top of the tint — they are what a red/green-blind reader actually reads, and a
/// test holds that each of them tells the three cases apart on its own.
public nonisolated enum DeltaDirection: Sendable, CaseIterable {
    /// The value went up, and `G-7.3` makes a positive delta green whether or not the increase is
    /// welcome: a bodyweight gain on a cut still draws ``ColorToken/positive``. The tint follows
    /// the arithmetic rather than the sentiment, and there is deliberately no override — a
    /// component that knew which direction was *good* would be a component that knew what it was
    /// measuring.
    case increase

    /// The value went down.
    case decrease

    /// The value did not move. Neutral in colour as well as in meaning: nothing is being reported
    /// as good or bad, so the semantic palette stays out of it (`G-7.3`).
    case unchanged

    /// The tint the indicator draws in.
    public var tint: ColorToken {
        switch self {
        case .increase: .positive
        case .decrease: .negative
        case .unchanged: .textSecondary
        }
    }

    /// The SF Symbol drawn beside the value — the cue that survives a monochrome rendering.
    public var symbolName: String {
        switch self {
        case .increase: "arrow.up"
        case .decrease: "arrow.down"
        case .unchanged: "minus"
        }
    }

    /// The character prefixed to the value. Written by the indicator rather than by the caller, so
    /// the cue cannot be forgotten at a call site. Empty for ``unchanged``, which has no sign to
    /// state — the glyph is that case's non-colour cue.
    ///
    /// The minus is U+2212, not a hyphen: it is the width of the plus, so a column of deltas lines
    /// up.
    public var sign: String {
        switch self {
        case .increase: "+"
        case .decrease: "\u{2212}"
        case .unchanged: ""
        }
    }
}

/// A signed change, drawn as glyph + sign + value (`G-7.3`, `G-4.5`).
///
/// Reads as one element to VoiceOver: the glyph is hidden and the sign is spoken as part of the
/// number, so nothing is announced twice and nothing is announced only in colour (`G-4.2`).
///
/// **Punctuation is forced on, because the sign is then the only non-visual cue.** Whether
/// VoiceOver speaks `+` and `−` is otherwise the reader's verbosity setting, and at its lowest
/// both signed cases announce identically — which leaves direction in the tint alone, exactly what
/// `G-4.5` forbids. Forcing it settles that without this module naming a word it would then have
/// to localize against the wrong bundle.
///
/// **The magnitude arrives as a `String`, not as a `Text`** — the one component here that does.
/// This view has to put a character *in front of* the caller's text, and the sign is only a
/// guarantee if the view writes it; a `Text` can be concatenated with another but not prefixed with
/// a character. It is rendered verbatim, so nothing is looked up in this package's bundle: a delta
/// magnitude is a formatted number the caller's own formatter localized, never prose.
public struct DeltaIndicator: View {
    private let direction: DeltaDirection
    private let value: String

    /// Builds an indicator for `value` moving in `direction`.
    ///
    /// - Parameters:
    ///   - direction: Which way the value moved.
    ///   - value: The magnitude, already formatted by the caller — *without* a sign, which this
    ///     view supplies.
    public init(_ direction: DeltaDirection, value: String) {
        self.direction = direction
        self.value = value
    }

    /// Glyph, sign and magnitude on one line, announced to VoiceOver as a single element.
    public var body: some View {
        HStack(spacing: Spacing.xxs.points) {
            Image(systemName: direction.symbolName)
                .accessibilityHidden(true)
            Text(verbatim: direction.sign + value)
        }
        .font(Typography.metricContext.font)
        .foregroundStyle(direction.tint)
        .accessibilityElement(children: .combine)
        .speechAlwaysIncludesPunctuation()
    }
}
