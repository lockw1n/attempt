import DesignSystem
import Foundation
import Localization
import PowerliftingCore
import SwiftUI

extension SetModifier {
    /// The name to draw for this modifier — the built-in term's own copy, or the spelling itself.
    ///
    /// **A term this version does not recognise falls back to its raw spelling, and that is the
    /// whole of `OpenVocabulary`'s preservation reaching the screen** (`FR-1.2.8`): there is no
    /// localised name for a word the user invented or a newer version wrote, and drawing nothing
    /// would be indistinguishable from the modifier not being there.
    var displayName: String {
        guard let term = known else { return rawValue }
        return String(localized: LoggingStrings.setModifierName(for: term))
    }
}

/// `FR-1.2.8`'s multi-select over the configurable modifier list, and the way into the list itself.
///
/// **A sheet of its own rather than a seventh row of controls in the set editor.** The editor is
/// already at `NFR-1.10`'s ceiling with six rows — T-1.23's toggle is what made its `.large` detent
/// necessary — and a wrapping grid of nine-plus chips is the tallest control the form could gain.
/// What the form gains instead is one summary row; everything the list needs room for is here.
///
/// **Its own `NavigationStack`, so the list editor is a push and not a second sheet.** A sheet over
/// a sheet buries the set being edited two presentations deep, and the way back out of one is a
/// gesture rather than a control (`G-4.2`).
///
/// **Nothing here writes to the set.** The selection lands in the draft and is written when the form
/// is confirmed, which is what makes **Cancel** on the form mean what it says.
struct SetModifierPicker: View {
    /// What the set being drafted carries. Bound, so a tap here lands in the draft directly.
    @Binding var applied: [SetModifier]

    /// The terms on offer (`FR-1.2.8`).
    let vocabulary: SetModifierVocabulary

    /// Closes the picker, back to the form.
    let dismiss: () -> Void

    /// What was applied when the picker opened.
    ///
    /// **Held, so a row cannot disappear from under the thumb that is using it.** A spelling the
    /// list does not offer is drawn only because a set carries it; read live, deselecting one would
    /// take its own row off the screen and leave no way back to it.
    @State private var opened: [SetModifier]

    /// Builds the picker.
    ///
    /// - Parameters:
    ///   - applied: What the set carries, bound to the draft.
    ///   - vocabulary: The terms on offer.
    ///   - dismiss: Closes the picker.
    init(
        applied: Binding<[SetModifier]>,
        vocabulary: SetModifierVocabulary,
        dismiss: @escaping () -> Void
    ) {
        _applied = applied
        self.vocabulary = vocabulary
        self.dismiss = dismiss
        _opened = State(initialValue: applied.wrappedValue)
    }

    /// Every term to draw a row for: the list, then anything this set carries that it does not
    /// offer.
    var rows: [SetModifier] {
        vocabulary.offered(with: opened + applied)
    }

    /// The rows, then the way into the list editor.
    var body: some View {
        NavigationStack {
            ScrollView {
                SetModifierSelection(
                    rows: rows,
                    applied: applied,
                    isOffered: { vocabulary.terms.contains($0) },
                    toggle: toggle,
                    destination: { SetModifierListEditor(vocabulary: vocabulary) }
                )
                .padding(Spacing.lg.points)
            }
            .background(ColorToken.background)
            .navigationTitle(Text(LoggingStrings.setModifierPickerTitle))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: dismiss) { Text(LoggingStrings.setModifierDoneAction) }
                }
            }
        }
    }

    /// Applies the term, or takes it off.
    ///
    /// - Parameter modifier: The term tapped.
    func toggle(_ modifier: SetModifier) {
        applied = Self.toggling(modifier, in: applied)
    }

    /// `applied` with `modifier` added if it was absent and removed if it was there.
    ///
    /// **A function rather than a mutation on the binding**, so the one rule this picker has can be
    /// asserted without a screen: applied twice it must return what it started with, which is what a
    /// row tapped twice does.
    ///
    /// Appended rather than inserted in the list's order: the storage layer sorts and deduplicates,
    /// so a position here would be a second answer to a question already settled — and reordering
    /// under the thumb is what a picker must not do.
    ///
    /// - Parameters:
    ///   - modifier: The term tapped.
    ///   - applied: What the set carries.
    /// - Returns: What it carries afterwards.
    static func toggling(_ modifier: SetModifier, in applied: [SetModifier]) -> [SetModifier] {
        guard let position = applied.firstIndex(of: modifier) else { return applied + [modifier] }
        var remaining = applied
        remaining.remove(at: position)
        return remaining
    }
}

/// The picker's rows, and the push into the list editor beneath them.
///
/// **A type of its own for ``SetEditorFields``' reason** (`TR-1.12`): `ImageRenderer` draws none of
/// a `ScrollView`'s content, so a reference taken over the picker itself would be a picture of a
/// navigation bar. It takes values rather than the vocabulary so a reference can render a list that
/// no `UserDefaults` suite has to hold.
struct SetModifierSelection<Destination: View>: View {
    /// Every term to draw, offered ones first.
    let rows: [SetModifier]

    /// Which of them the set carries.
    let applied: [SetModifier]

    /// Whether the list still offers a term — `false` draws the unlisted note.
    let isOffered: (SetModifier) -> Bool

    /// Applies a term or takes it off.
    let toggle: (SetModifier) -> Void

    /// Where **Manage list** leads — the list editor, or an `EmptyView` in a rendering that has no
    /// stack above it.
    @ViewBuilder let destination: Destination

    /// The rows, then the command that edits the list they come from.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.points) {
            ForEach(rows, id: \.rawValue) { modifier in
                SetModifierRow(
                    modifier: modifier,
                    isApplied: applied.contains(modifier),
                    isUnlisted: !isOffered(modifier),
                    toggle: { toggle(modifier) }
                )
            }
            manageCommand
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The way into the list editor.
    private var manageCommand: some View {
        NavigationLink(destination: { destination }, label: { manageLabel })
            .buttonStyle(.plain)
    }

    /// **Manage list**, as the command draws it.
    private var manageLabel: some View {
        HStack(spacing: Spacing.sm.points) {
            Image(systemName: "slider.horizontal.3").accessibilityHidden(true)
            Text(LoggingStrings.setModifierManageAction)
            Spacer(minLength: Spacing.sm.points)
            Image(systemName: "chevron.right")
                .font(Typography.caption.font)
                .accessibilityHidden(true)
        }
        .font(Typography.actionLabel.font)
        .foregroundStyle(ColorToken.brandAccent)
        .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// One term in the picker: its name, whether the set carries it, and whether the list still offers
/// it.
///
/// **A checkmark rather than a tint** (`G-4.5`): applied and not applied differ in shape, so the
/// selection survives a monochrome rendering. It is a `Button` carrying an accessibility *value*
/// rather than a `Toggle`, on the set editor's measured finding — a UIKit switch inside a presented
/// sheet never receives the tap.
struct SetModifierRow: View {
    /// The term.
    let modifier: SetModifier

    /// Whether the set carries it.
    let isApplied: Bool

    /// Whether the list has stopped offering it — a term from a newer version, or one removed since
    /// the set was logged.
    let isUnlisted: Bool

    /// Applies it, or takes it off.
    let toggle: () -> Void

    /// The mark, the name, and the note where the term is no longer offered.
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Spacing.sm.points) {
                Image(systemName: isApplied ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isApplied ? ColorToken.brandAccent : ColorToken.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs.points) {
                    Text(verbatim: modifier.displayName)
                        .font(Typography.body.font)
                        .foregroundStyle(ColorToken.textPrimary)
                    if isUnlisted {
                        Text(LoggingStrings.setModifierUnlisted)
                            .font(Typography.caption.font)
                            .foregroundStyle(ColorToken.textTertiary)
                    }
                }
                Spacer(minLength: Spacing.sm.points)
            }
            .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
            .padding(.horizontal, Spacing.md.points)
            .background(
                ColorToken.surfaceRaised, in: .rect(cornerRadius: CornerRadius.control.points)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(LoggingStrings.setModifierState(isApplied: isApplied)))
    }
}
