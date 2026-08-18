import DesignTokens
import SwiftUI

/// A titled group: a heading, then the group's content on a card (`G-7.1`).
///
/// The heading sits **outside** the card rather than inside it. A heading on the surface it
/// describes reads as the first row of that surface; above it, it reads as a label for the whole
/// group, which is what a grouped section is.
///
/// **The title arrives as a `Text` the caller built.** A `LocalizedStringKey` parameter would be
/// resolved against this package's bundle rather than the app's, so a design-system component that
/// took one would quietly break every localized string passed through it (`G-3.4`). Nothing in
/// `DesignSystem` declares user-visible text; every string in this module comes from its caller.
public struct GroupedSection<Content: View>: View {
    private let title: Text
    private let content: Content

    /// Builds a section titled `title`.
    ///
    /// - Parameters:
    ///   - title: The group's heading, built by the caller so it is localized in the caller's
    ///     bundle.
    ///   - content: The group's rows, stacked at the same measure as the card's own inset. Matching
    ///     the two is what keeps a row's gap to its neighbour from reading as tighter than its
    ///     gap to the card's edge, which is what makes a stack of rows look like one block of text.
    public init(_ title: Text, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    /// The heading, then the group's rows on a card beneath it.
    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.points) {
            title
                .font(Typography.sectionHeading.font)
                .foregroundStyle(ColorToken.textPrimary)
            Card {
                VStack(alignment: .leading, spacing: Spacing.lg.points) {
                    content
                }
            }
        }
    }
}
