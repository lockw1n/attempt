import SwiftUI

/// A search field drawn in a screen's own content, not in its navigation bar (`FR-16.5.4`).
///
/// **The component exists because `.searchable` cannot be used here.** SwiftUI places that modifier
/// in the enclosing navigation bar, and every screen in this app hides the bar behind a custom
/// header — so the system's affordance renders collapsed and is reached by pulling the content down,
/// which is a gesture nothing on screen advertises. A field the screen draws itself is visible at
/// rest, which is the whole of what the requirement asks for.
///
/// **Not a `DesignSystem` string except for the clear button.** The prompt names what is being
/// searched and that is the screen's knowledge, so it arrives as a `LocalizedStringResource` the
/// caller built; "Clear" is the same everywhere, which is this module's rule for owning a string.
public struct SearchField: View {
    /// What the user has typed.
    @Binding private var text: String

    /// The placeholder — what this field searches, in the caller's words.
    private let prompt: LocalizedStringResource

    /// Builds the field.
    ///
    /// - Parameters:
    ///   - text: The query, bound to whatever holds it.
    ///   - prompt: The placeholder naming what is searched.
    public init(text: Binding<String>, prompt: LocalizedStringResource) {
        _text = text
        self.prompt = prompt
    }

    /// A magnifier, the field, and a clear control once there is something to clear.
    ///
    /// The magnifier is hidden from VoiceOver: the field's own prompt already says what it is, and
    /// a decorative glyph announced beside it is a second stop saying nothing (`G-4.2`). The clear
    /// button appears only with text in the field, so an empty field has no control that would do
    /// nothing.
    public var body: some View {
        HStack(spacing: Spacing.sm.points) {
            Image(systemName: "magnifyingglass")
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textSecondary)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: Text(prompt)) {
                Text(prompt)
            }
            .font(Typography.body.font)
            .foregroundStyle(ColorToken.textPrimary)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .searchKeyboard()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Typography.body.font)
                        .foregroundStyle(ColorToken.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(DesignSystemStrings.searchClear))
            }
        }
        .padding(.horizontal, Spacing.md.points)
        .frame(minHeight: TouchTarget.standard.points)
        .background(
            ColorToken.surfaceRaised,
            in: .rect(cornerRadius: CornerRadius.control.points)
        )
    }
}

extension View {
    /// The keyboard behaviour a search field wants, where the platform has one.
    ///
    /// **`#if os(iOS)`, ``DecimalKeyboard``'s shape and for its reason**: both modifiers are UIKit's
    /// and this package builds for macOS too, where `swift build` is the check that runs. An
    /// exercise name is not a sentence, so autocapitalising the first letter would put a capital in
    /// front of every query the moment the field is tapped.
    fileprivate func searchKeyboard() -> some View {
        #if os(iOS)
            self
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
        #else
            self
        #endif
    }
}
