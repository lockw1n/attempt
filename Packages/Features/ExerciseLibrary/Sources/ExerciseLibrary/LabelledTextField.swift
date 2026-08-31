import DesignSystem
import SwiftUI

/// A labelled text box with a sentence under it — the shape both name fields take.
///
/// Extracted because the two differ only in their strings and in what goes under the box; the
/// label, the box and its chrome were identical, and a second copy of them is a second place to
/// forget a Dynamic Type change — which is not hypothetical: the caption's own wrapping fix below
/// was needed on one of the two and would have been applied to only that one.
struct LabelledTextField<Caption: View>: View {
    /// The label above the box, and the field's accessibility label — the visible one is hidden
    /// so the two cannot drift apart.
    let label: LocalizedStringResource

    /// The placeholder inside an empty box.
    let prompt: LocalizedStringResource

    /// What the user is typing.
    @Binding var text: String

    /// The sentence under the box, which may be nothing.
    let caption: Caption

    init(
        label: LocalizedStringResource,
        prompt: LocalizedStringResource,
        text: Binding<String>,
        @ViewBuilder caption: () -> Caption
    ) {
        self.label = label
        self.prompt = prompt
        self._text = text
        self.caption = caption()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.points) {
            Text(label)
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            TextField(text: $text, prompt: Text(prompt)) {
                Text(label)
            }
            .labelsHidden()
            .font(Typography.body.font)
            .foregroundStyle(ColorToken.textPrimary)
            .textFieldStyle(.plain)
            .padding(Spacing.md.points)
            .background(
                ColorToken.surfaceRaised,
                in: .rect(cornerRadius: CornerRadius.control.points)
            )
            // Without this the sentence TRUNCATES rather than wraps wherever the section below is
            // tall enough to squeeze it — measured on the built-in form, at DEFAULT Dynamic Type,
            // where the five catalogue-owned facts are what does the squeezing (`G-4.1`).
            caption
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
