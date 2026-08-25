import DesignSystem
import Foundation
import PowerliftingCore
import SwiftUI

/// `FR-1.4.1`'s way in: the loading for the weight the set editor currently holds, and the tap that
/// opens the whole answer.
///
/// **This is the entry point, and it is here rather than on a logged set's row.** The task's brief
/// named "tap the weight in the set row", but T-1.25 has since given that tap to the editor — and
/// deliberately, having removed the nested-control shape where which control receives a tap depends
/// on ancestry rather than on where the thumb landed. Reinstating a second meaning for the same tap
/// would put that back. What the brief asked for still holds one level down: tapping a set's weight
/// opens this form over that weight, and the loading is the line under it.
///
/// **It is a *target* weight here, which is what `FR-1.4.1` says.** The number in the field is the
/// one the user is about to put on the bar and can still change with the ± pair beside it; a logged
/// set's weight is a past fact.
///
/// **Drawn only once the field holds a weight.** A row over a blank or refused entry would be a
/// control that starts dead on every new set — the modifier line on a set row's rule, one screen
/// along — and this form is already at `NFR-1.10`'s ceiling.
struct PlateLoadingRow: View {
    /// The weight the form currently holds.
    let target: Weight

    /// What that weight loads to, or `nil` when there is no equipment to load against.
    let result: PlateLoadingResult?

    /// The unit the plates are drawn in (`G-3.1`).
    let unit: MassUnit

    /// Opens the calculator over ``target``.
    let open: () -> Void

    /// Which locale the loads are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The row: a label, the line, and a chevron — the modifiers row's shape, because it is the same
    /// kind of control (a summary that opens the screen it summarises).
    var body: some View {
        FieldRow(label: Text(LoggingStrings.plateRowLabel), hint: nil) {
            Button(action: open) {
                HStack(spacing: Spacing.sm.points) {
                    Text(verbatim: summary)
                        .font(Typography.body.font)
                        .foregroundStyle(ColorToken.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Spacing.sm.points)
                    Image(systemName: "chevron.right")
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.textTertiary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: TouchTarget.logging.points)
                .padding(.horizontal, Spacing.md.points)
                .background(
                    ColorToken.surfaceRaised, in: .rect(cornerRadius: CornerRadius.control.points)
                )
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(LoggingStrings.plateRowLabel))
            // The line as a *value* and not as the label, on the modifiers row's argument (`G-4.2`):
            // combining the children builds a label from them and a label written here replaces it,
            // so what the bar actually takes would be announced nowhere.
            .accessibilityValue(Text(verbatim: summary))
        }
    }

    /// The line: the per-side plates, the refusal, or — before the equipment has been read — the
    /// same words the screen behind this row is showing.
    private var summary: String {
        guard let result else { return String(localized: LoggingStrings.plateRowUnknown) }
        return PlateLoadingSummary.row(result, unit: unit, locale: locale)
    }
}

/// `FR-1.4.1`'s per-side loading and `FR-1.4.4`'s two nearest weights, presented over the set
/// editor.
///
/// **Presented rather than pushed, and it carries no `Route`** — the set editor's own reason, one
/// presentation further out: a calculator opened over a half-filled set is not a place in the app,
/// and a restored stack that reopened it would compute a loading for a draft that no longer exists.
/// One presentation deep and no further, exactly as the modifier picker is.
struct PlateCalculatorSheet: View {
    /// The weight being loaded for.
    let target: Weight

    /// The equipment it is loaded against.
    let store: PlateCalculatorStore

    /// The unit the loads are drawn in (`G-3.1`).
    let unit: MassUnit

    /// Closes the sheet.
    let dismiss: () -> Void

    /// Whether `FR-1.4.3`'s switcher is on this sheet's own stack.
    ///
    /// **Pushed onto the sheet's `NavigationStack` rather than presented over it**: the calculator
    /// is already a presentation, and a second sheet over the first is where a control starts losing
    /// taps to the presentation's own gestures. It is the sheet's rather than a `Route` for the
    /// reason this screen has none — a calculator opened over a half-filled set is not a place the
    /// app can be restored to, so nothing on it can be either.
    @State private var isChoosingEquipment = false

    /// The content, with the sheet's own chrome around it.
    var body: some View {
        NavigationStack {
            ScrollView {
                PlateCalculatorContent(
                    target: target,
                    state: PlateEquipmentState.current(
                        hasLoaded: store.hasLoaded,
                        hasEquipment: store.equipment != nil,
                        failure: store.failure
                    ),
                    equipment: store.equipment,
                    unit: unit,
                    retry: { Task { await store.load() } },
                    chooseEquipment: { isChoosingEquipment = true }
                )
                .padding(Spacing.lg.points)
            }
            .background(ColorToken.background)
            .navigationDestination(isPresented: $isChoosingEquipment) {
                EquipmentProfilesView(store: store)
            }
            .navigationTitle(Text(LoggingStrings.plateTitle))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: dismiss) { Text(LoggingStrings.plateDoneAction) }
                }
            }
        }
    }
}

/// What the calculator draws, without the sheet around it.
///
/// **A type of its own for ``SetEditorFields``' reason** (`TR-1.12`): `ImageRenderer` draws none of
/// a `ScrollView`'s content, so a reference taken over the sheet would be a picture of a navigation
/// bar. It takes values rather than the store, so a reference renders without one.
struct PlateCalculatorContent: View {
    /// The weight being loaded for.
    let target: Weight

    /// Which of `FR-1.13.1`'s states the screen is in.
    let state: PlateEquipmentState

    /// The gym, where one is loaded.
    let equipment: LoadedEquipment?

    /// The unit the loads are drawn in (`G-3.1`).
    let unit: MassUnit

    /// Reads the equipment again — offered on the one failure a second read could resolve.
    let retry: () -> Void

    /// Opens the gyms (`FR-1.4.3`) — from the empty state, and from the equipment section under an
    /// answer this screen already gave.
    let chooseEquipment: () -> Void

    /// Which locale the loads are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The target, then whichever state the equipment read left the screen in.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            targetHeader
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The weight being loaded for — drawn whatever the equipment did, because it is the user's own
    /// number and does not depend on the read.
    private var targetHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs.points) {
            Text(LoggingStrings.plateTargetLabel)
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            Text(verbatim: PlateLoadingSummary.load(target, in: unit, locale: locale))
                .font(Typography.numericValue.font)
                .foregroundStyle(ColorToken.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    /// The screen's four states (`FR-1.13.1`), each one of T-1.09's shared components.
    ///
    /// **The empty state is a gym that has not been set up, and not a gym with no plates.** A
    /// profile stocking nothing is a gym where exactly one weight loads — the bare bar — which the
    /// sections below say in words; rendering that as "nothing here yet" would report a real answer
    /// as an absence. What is genuinely empty is a lifter who has configured no equipment at all,
    /// and its action is the only thing that produces some (`FR-1.13.2`).
    ///
    /// **No offline state**: the profile is a local row (`G-2.1`, `G-2.3`), so a connection has
    /// nothing to do with whether this screen can answer.
    ///
    /// **The two error states differ by their retry**, on the active session screen's precedent: a
    /// read that failed may succeed on a second attempt, where a profile whose plate lists cannot
    /// describe a gym refuses identically every time — a button that re-answers the same way is
    /// worse than no button, and the fix is editing the profile.
    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            LoadingStateView()
        case .noEquipment:
            EmptyStateView(
                symbolName: "dumbbell",
                headline: Text(LoggingStrings.plateNoEquipmentHeadline),
                message: Text(LoggingStrings.plateNoEquipmentMessage),
                action: StateAction(
                    Text(LoggingStrings.plateNoEquipmentAction), handler: chooseEquipment)
            )
        case .readFailed:
            ErrorStateView(
                headline: Text(LoggingStrings.plateErrorHeadline),
                message: Text(LoggingStrings.plateErrorMessage),
                retry: retry
            )
        case .unusable:
            ErrorStateView(
                headline: Text(LoggingStrings.plateUnusableHeadline),
                message: Text(LoggingStrings.plateUnusableMessage)
            )
        case .ready:
            if let equipment {
                loaded(equipment)
            }
        }
    }

    /// The answer, and the gym it was computed on.
    ///
    /// - Parameter equipment: The gym.
    /// - Returns: The sections.
    @ViewBuilder private func loaded(_ equipment: LoadedEquipment) -> some View {
        switch equipment.calculator.loading(for: target) {
        case .exact(let loading):
            GroupedSection(Text(LoggingStrings.plateExactSection)) {
                loadingRow(loading)
            }
        case .nearest(let below, let above):
            // `FR-1.4.4` wants both, and they are two sections rather than one row of two numbers:
            // each carries its own plate list, and either may be absent while the other is not.
            GroupedSection(Text(LoggingStrings.plateBelowSection)) {
                arm(
                    below,
                    headline: LoggingStrings.plateBelowNoneHeadline,
                    message: LoggingStrings.plateBelowNoneMessage
                )
            }
            GroupedSection(Text(LoggingStrings.plateAboveSection)) {
                arm(
                    above,
                    headline: LoggingStrings.plateAboveNoneHeadline,
                    message: LoggingStrings.plateAboveNoneMessage
                )
            }
        }
        equipmentSection(equipment)
    }

    /// One side of `FR-1.4.4`'s answer, or `FR-1.13.3`'s explanation of why there is none.
    ///
    /// **An absent arm is `InsufficientDataView` rather than a blank.** It is a derived value the
    /// data cannot support — nothing loads below the bare bar, and a gym's plates only reach so far
    /// — and each half says which of the two it is, since the remedies are nothing alike.
    ///
    /// `PlateLoadingResult` guarantees the two are never both absent, so this screen never draws two
    /// of these at once; it surfaces that guarantee rather than restating it.
    ///
    /// - Parameters:
    ///   - loading: The loading on this side, where there is one.
    ///   - headline: What cannot be shown.
    ///   - message: Why, and what would change it.
    /// - Returns: The row, or the placeholder.
    @ViewBuilder private func arm(
        _ loading: PlateLoading?,
        headline: LocalizedStringResource,
        message: LocalizedStringResource
    ) -> some View {
        if let loading {
            loadingRow(loading)
        } else {
            InsufficientDataView(headline: Text(headline), message: Text(message))
        }
    }

    /// One loading: what the bar comes to, and what goes on each side of it.
    ///
    /// One VoiceOver element, because it is one answer (`G-4.2`).
    ///
    /// - Parameter loading: The loaded bar.
    /// - Returns: The row.
    private func loadingRow(_ loading: PlateLoading) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs.points) {
            Text(verbatim: PlateLoadingSummary.load(loading.totalWeight, in: unit, locale: locale))
                .font(Typography.numericValue.font)
                .foregroundStyle(ColorToken.textPrimary)
            Text(LoggingStrings.platePerSideLabel)
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            Text(verbatim: PlateLoadingSummary.perSide(loading, unit: unit, locale: locale))
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Which gym the numbers above were computed on.
    ///
    /// **Named rather than assumed** (`G-6.2`): a loading is only true of one bar and one plate set,
    /// and the interim default is a set the user has not chosen — so it says so, in the catalogue's
    /// words rather than as a name on a record nobody authored.
    ///
    /// - Parameter equipment: The gym.
    /// - Returns: The section.
    private func equipmentSection(_ equipment: LoadedEquipment) -> some View {
        GroupedSection(Text(LoggingStrings.plateEquipmentSection)) {
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                    Text(verbatim: equipment.displayName)
                        .font(Typography.body.font)
                        .foregroundStyle(ColorToken.textPrimary)
                    Text(barLine(of: equipment))
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                // `FR-1.4.3` from here rather than from Settings alone: the moment a loading looks
                // wrong is the moment the user knows which gym they are actually in.
                Button(action: chooseEquipment) {
                    Text(LoggingStrings.plateChangeEquipmentAction)
                        .font(Typography.actionLabel.font)
                        .foregroundStyle(ColorToken.brandAccent)
                        .frame(maxWidth: .infinity, minHeight: TouchTarget.logging.points, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The bar and its collars, which is the half of a profile a plate list does not show.
    ///
    /// - Parameter equipment: The gym.
    /// - Returns: The line.
    private func barLine(of equipment: LoadedEquipment) -> LocalizedStringResource {
        LoggingStrings.plateEquipmentBar(
            bar: PlateLoadingSummary.render(equipment.calculator.bar, in: unit, locale: locale),
            collar: PlateLoadingSummary.render(
                equipment.calculator.collar, in: unit, locale: locale)
        )
    }
}
