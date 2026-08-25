import DesignSystem
import Localization
import PowerliftingCore
import SwiftUI

/// `FR-1.2.8`'s "configurable": adding, renaming and removing the terms the picker offers.
///
/// **The nine built-ins are shown and not offered for editing.** They are what `SetModifierTerm`
/// decodes, so a list that could delete one would leave the app recognising a term it declines to
/// offer.
///
/// **Editing this list never rewrites a logged set** (`G-1.6`), and the hint at the top says so —
/// it is the one consequence a user cannot see. A set that recorded a term keeps recording it; the
/// spelling merely stops being recognised, which is the case `OpenVocabulary` exists for.
struct SetModifierListEditor: View {
    /// The list being edited.
    let vocabulary: SetModifierVocabulary

    /// The scrolling frame around the fields.
    var body: some View {
        ScrollView {
            SetModifierListFields(vocabulary: vocabulary)
                .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(LoggingStrings.setModifierManageTitle))
    }
}

/// The list editor's own contents, without the scroll view around them.
///
/// **A type of its own for ``SetEditorFields``' reason** (`TR-1.12`): `ImageRenderer` lays a
/// `ScrollView`'s content out and draws none of it, so a reference over the screen would be a
/// picture of a navigation bar.
struct SetModifierListFields: View {
    /// The list being edited.
    let vocabulary: SetModifierVocabulary

    /// What the user is typing into the add field.
    @State private var newTerm: String = ""

    /// Whether the last attempt to add was refused — empty, or already on the list.
    @State private var showsRefusal = false

    /// The hint, the add field, the user's own terms, then the built-ins.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            Text(LoggingStrings.setModifierManageHint)
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            addField
            customSection
            builtInSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The field a new term is typed into, and the command beside it.
    ///
    /// **A refusal rather than a disabled command**, on the set editor's rule: the two reasons a
    /// term is refused — blank, and already on the list — are invisible on a dimmed button, and the
    /// second one is the likely one.
    private var addField: some View {
        FieldRow(label: Text(LoggingStrings.setModifierAddLabel), hint: nil) {
            VStack(alignment: .leading, spacing: Spacing.xs.points) {
                HStack(spacing: Spacing.sm.points) {
                    ModifierTextField(
                        text: $newTerm, label: LoggingStrings.setModifierAddLabel, submit: add)
                    Button(action: add) { Text(LoggingStrings.setModifierAddAction) }
                        .buttonStyle(.plain)
                        .font(Typography.actionLabel.font)
                        .foregroundStyle(ColorToken.brandAccent)
                        .frame(minHeight: TouchTarget.standard.points)
                        .padding(.horizontal, Spacing.md.points)
                        .contentShape(.rect)
                }
                if showsRefusal {
                    FieldRefusal(message: Text(LoggingStrings.setModifierAddRefusal))
                }
            }
        }
    }

    /// The user's own terms, each renamable and removable — or the sentence that says there are
    /// none.
    private var customSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.points) {
            Text(LoggingStrings.setModifierCustomSection)
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            if vocabulary.custom.isEmpty {
                Text(LoggingStrings.setModifierCustomEmpty)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(vocabulary.custom, id: \.self) { spelling in
                    CustomModifierRow(
                        spelling: spelling,
                        rename: { vocabulary.rename(SetModifier(rawValue: spelling), to: $0) },
                        remove: { vocabulary.remove(SetModifier(rawValue: spelling)) }
                    )
                }
            }
        }
    }

    /// The nine, listed so the user can see what they already have before adding a tenth.
    private var builtInSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.points) {
            Text(LoggingStrings.setModifierBuiltInSection)
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            ForEach(SetModifierVocabulary.builtIn, id: \.rawValue) { modifier in
                Text(verbatim: modifier.displayName)
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: TouchTarget.standard.points)
            }
        }
    }

    /// Adds what is in the field, or says why it could not be.
    private func add() {
        if vocabulary.add(newTerm) == nil {
            showsRefusal = !newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            newTerm = ""
            showsRefusal = false
        }
    }
}

/// One of the user's own terms: renamable in place, removable beside it.
///
/// **Renamed on submit rather than on every keystroke**, and the difference is that a rename is a
/// write: keystroke by keystroke, typing `chains` over `chain` would first collide with itself and
/// then leave the list holding every prefix the user passed through.
///
/// A refused rename — blank, or a spelling already on the list — puts the field back rather than
/// leaving it holding a name that is not the term's.
struct CustomModifierRow: View {
    /// The term's spelling, as stored.
    let spelling: String

    /// Renames it. Answers whether anything changed.
    let rename: (String) -> Bool

    /// Stops offering it.
    let remove: () -> Void

    /// What is in the field.
    @State private var text: String

    /// Builds the row over a term.
    ///
    /// - Parameters:
    ///   - spelling: The term's spelling.
    ///   - rename: Renames it, answering whether anything changed.
    ///   - remove: Stops offering it.
    init(spelling: String, rename: @escaping (String) -> Bool, remove: @escaping () -> Void) {
        self.spelling = spelling
        self.rename = rename
        self.remove = remove
        _text = State(initialValue: spelling)
    }

    /// The field, then the removal.
    var body: some View {
        HStack(spacing: Spacing.sm.points) {
            ModifierTextField(text: $text, label: LoggingStrings.setModifierAddLabel) {
                if !rename(text) { text = spelling }
            }
            Button(action: remove) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(ColorToken.negative)
                    .frame(
                        minWidth: TouchTarget.standard.points, minHeight: TouchTarget.standard.points
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(LoggingStrings.setModifierRemoveAction))
        }
    }
}

/// A term's text field, drawn the way the set editor draws its own.
///
/// A shape of its own so the add field and every rename field are one declaration rather than three.
struct ModifierTextField: View {
    /// What is in it.
    @Binding var text: String

    /// What it is, for VoiceOver and for the placeholder.
    let label: LocalizedStringResource

    /// What the return key does.
    let submit: () -> Void

    /// The field.
    var body: some View {
        TextField(text: $text) { Text(label) }
            .textFieldStyle(.plain)
            .font(Typography.body.font)
            .foregroundStyle(ColorToken.textPrimary)
            .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
            .padding(.horizontal, Spacing.md.points)
            .background(
                ColorToken.surfaceRaised, in: .rect(cornerRadius: CornerRadius.control.points)
            )
            .accessibilityLabel(Text(label))
            .onSubmit(submit)
    }
}
