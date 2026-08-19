import SwiftUI

/// One entry in the type scale: a text style, a weight, and whether digits are monospaced.
///
/// Kept separate from ``Typography`` so the scale can be inspected and tested as data. Comparing
/// two `Font` values says nothing useful — this is what a test can assert on.
///
/// **There is no size.** Every style names a `Font.TextStyle`, which is what makes the scale
/// respond to the user's Dynamic Type setting (`G-7.6`, `G-4.1`); a token carrying a point size
/// would be a fixed-size font wearing a token's name.
public struct TypeStyle: Sendable, Hashable {
    /// The Dynamic Type style the token scales with.
    public let textStyle: Font.TextStyle

    /// The SF Pro weight. The design is always `.default`, which is SF Pro (`G-7.6`).
    public let weight: Font.Weight

    /// Whether digits are fixed-width, so a changing number does not shift the glyphs beside it.
    public let usesMonospacedDigits: Bool

    /// Builds a scale entry. Only ``Typography`` should call this — a style declared anywhere else
    /// is a font outside the scale, which is what `G-7.6` forbids.
    public init(textStyle: Font.TextStyle, weight: Font.Weight, usesMonospacedDigits: Bool = false) {
        self.textStyle = textStyle
        self.weight = weight
        self.usesMonospacedDigits = usesMonospacedDigits
    }

    /// The SwiftUI font this entry describes.
    public var font: Font {
        let font = Font.system(textStyle, design: .default, weight: weight)
        return usesMonospacedDigits ? font.monospacedDigit() : font
    }
}

/// The type scale (`G-7.6`). Every piece of text in the app names one of these roles.
///
/// The cases are **roles, not sizes**: `.metricNumeral` says what the text is for, so the scale can
/// be retuned in one place without a search for "the large bold one".
///
/// **Every role resolves to its own ``TypeStyle``, and a test holds that.** Two roles that come out
/// identical are either one role with two names, or a distinction the scale has not expressed yet;
/// both want deciding rather than shipping.
///
/// `G-7.5`'s metric tile is three of these in order: ``metricLabel`` above, ``metricNumeral`` as
/// the anchor, ``metricContext`` beneath.
public enum Typography: Sendable, CaseIterable {
    /// A screen's own title, in the navigation bar or as the first thing in its scroll view.
    case screenTitle

    /// The heading of a grouped section within a screen.
    case sectionHeading

    /// The title inside a card, subordinate to ``sectionHeading``.
    case cardTitle

    /// The large numeral a metric tile is built around — the visual anchor of the card (`G-7.5`).
    /// Monospaced digits: this number changes as the user logs, and the layout must not twitch.
    case metricNumeral

    /// The small label above a metric's numeral, naming what the number is.
    case metricLabel

    /// The small context line beneath a metric's numeral — a delta, a date, a qualifier.
    case metricContext

    /// Running text: descriptions, notes, and anything read as a sentence.
    case body

    /// A weight, rep count or RPE inside a row of logged work. Monospaced digits, so a column of
    /// sets aligns without a table.
    case numericValue

    /// Secondary annotation beneath body text, and the smallest role in the scale.
    case caption

    /// The label of a button or other tappable control. Body-sized rather than heading-sized: a
    /// control's label is read as part of the content around it, not as a heading over it.
    case actionLabel

    /// The scale entry this role resolves to.
    public var style: TypeStyle {
        switch self {
        case .screenTitle: TypeStyle(textStyle: .largeTitle, weight: .bold)
        case .sectionHeading: TypeStyle(textStyle: .headline, weight: .semibold)
        case .cardTitle: TypeStyle(textStyle: .title3, weight: .semibold)
        case .metricNumeral: TypeStyle(textStyle: .largeTitle, weight: .bold, usesMonospacedDigits: true)
        case .metricLabel: TypeStyle(textStyle: .caption, weight: .medium)
        case .metricContext: TypeStyle(textStyle: .footnote, weight: .regular)
        case .body: TypeStyle(textStyle: .body, weight: .regular)
        case .numericValue: TypeStyle(textStyle: .body, weight: .semibold, usesMonospacedDigits: true)
        case .caption: TypeStyle(textStyle: .caption, weight: .regular)
        case .actionLabel: TypeStyle(textStyle: .body, weight: .semibold)
        }
    }

    /// The SwiftUI font for this role — `Text("…").font(Typography.body.font)`.
    public var font: Font { style.font }
}
