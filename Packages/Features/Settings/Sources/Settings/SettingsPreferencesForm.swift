import DesignSystem
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// Every preference `FR-1.10.1` and `FR-1.10.2` name, over one loaded row.
///
/// **A pure function of the record**, which is what makes it snapshot-testable and what keeps the
/// eight controls from needing eight callbacks: each one mutates its own copy of the row it is
/// drawing and hands the whole thing back, so a control cannot clear a column it never read.
struct SettingsPreferencesForm: View {
    /// The row every control reads its selection from.
    let settings: UserSettings

    /// The last write that failed, as a diagnostic, or `nil`.
    let writeFailure: String?

    /// Moves one field on the stored row. Takes the change rather than the row, so a control
    /// cannot hand back a copy that was published before a write still in flight.
    let apply: (@escaping (inout UserSettings) -> Void) -> Void

    /// The locale the steps and increments render for.
    @Environment(\.locale) private var locale

    /// The five sections, in the order a lifter meets them.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            if let writeFailure {
                writeFailureCard(writeFailure)
            }
            units
            estimator
            rounding
            appearance
            workout
        }
    }

    /// A failed write, reported *above* the controls rather than in place of them.
    ///
    /// **Not `ErrorStateView`** (`FR-1.13.1`), and the difference is what the state means: that
    /// component is a scaffold that replaces a screen whose content could not be read, where this
    /// row is still loaded and still editable — replacing it would take away the retry, which is
    /// the next tap. The failed *read* one screen up does use the shared component.
    private func writeFailureCard(_ diagnostic: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                Text(SettingsStrings.writeErrorTitle)
                    .font(Typography.cardTitle.font)
                    .foregroundStyle(ColorToken.textPrimary)
                Text(verbatim: diagnostic)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
            }
        }
    }

    /// `G-3.1`'s unit and `G-3.3`'s step — the pair, because neither reads on its own.
    private var units: some View {
        GroupedSection(Text(SettingsStrings.unitsTitle)) {
            Picker(selection: binding(\.displayUnit)) {
                ForEach(MassUnit.allCases, id: \.self) { unit in
                    Text(SettingsStrings.unitSymbol(for: unit)).tag(unit)
                }
            } label: {
                Text(SettingsStrings.unitsPicker)
            }
            .pickerStyle(.segmented)

            menuRow(SettingsStrings.precisionPicker) {
                Picker(selection: binding(\.displayPrecision)) {
                    Text(SettingsStrings.precisionAutomatic)
                        .tag(DisplayPrecision?.none)
                    ForEach(precisions, id: \.self) { precision in
                        Text(verbatim: stepLabel(precision)).tag(DisplayPrecision?.some(precision))
                    }
                } label: {
                    Text(SettingsStrings.precisionPicker)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            caption(SettingsStrings.precisionDetail)
        }
    }

    /// `FR-1.7.2`'s formula and `FR-1.7.1`'s window: what an estimate is computed with, and what
    /// it is computed over.
    private var estimator: some View {
        GroupedSection(Text(SettingsStrings.estimatorTitle)) {
            menuRow(SettingsStrings.estimatorPicker) {
                Picker(selection: binding(\.e1RMFormula)) {
                    ForEach(E1RMFormulaID.allCases, id: \.self) { formula in
                        Text(SettingsStrings.formulaName(for: formula)).tag(formula)
                    }
                } label: {
                    Text(SettingsStrings.estimatorPicker)
                }
                // Hidden rather than absent: the menu draws only its selection, so without the
                // row label beside it the control reads as a bare surname — measured in the
                // simulator. The picker keeps the same label for VoiceOver, which is what
                // `.labelsHidden()` leaves behind.
                .labelsHidden()
                .pickerStyle(.menu)
            }
            caption(SettingsStrings.estimatorDetail)

            menuRow(SettingsStrings.lookbackPicker) {
                Picker(selection: binding(\.e1RMLookbackDays)) {
                    ForEach(lookbackWindows, id: \.self) { days in
                        Text(SettingsStrings.lookbackDays(days)).tag(days)
                    }
                } label: {
                    Text(SettingsStrings.lookbackPicker)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            caption(SettingsStrings.lookbackDetail)
        }
    }

    /// `FR-1.5.1.6`'s loadable step — what a bar can actually take, which is not what a number
    /// reads as.
    private var rounding: some View {
        GroupedSection(Text(SettingsStrings.roundingTitle)) {
            menuRow(SettingsStrings.roundingIncrement) {
                Picker(selection: binding(\.defaultRoundingIncrement)) {
                    ForEach(increments, id: \.self) { increment in
                        Text(verbatim: incrementLabel(increment)).tag(increment)
                    }
                } label: {
                    Text(SettingsStrings.roundingIncrement)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            menuRow(SettingsStrings.roundingStrategy) {
                Picker(selection: binding(\.defaultRoundingStrategy)) {
                    ForEach(RoundingStrategy.allCases, id: \.self) { strategy in
                        Text(SettingsStrings.strategyName(for: strategy)).tag(strategy)
                    }
                } label: {
                    Text(SettingsStrings.roundingStrategy)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            caption(SettingsStrings.roundingDetail)
        }
    }

    /// `FR-1.10.2`: the theme, and the one accent there is.
    private var appearance: some View {
        GroupedSection(Text(SettingsStrings.appearanceTitle)) {
            Picker(selection: binding(\.theme)) {
                ForEach(ThemePreference.allCases, id: \.self) { theme in
                    Text(SettingsStrings.themeName(for: theme)).tag(theme)
                }
            } label: {
                Text(SettingsStrings.themePicker)
            }
            .pickerStyle(.segmented)

            HStack {
                Text(SettingsStrings.accentLabel)
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.textSecondary)
                Spacer(minLength: Spacing.sm.points)
                Circle()
                    .fill(ColorToken.brandAccent)
                    .frame(width: Spacing.md.points, height: Spacing.md.points)
                    .accessibilityHidden(true)
                Text(SettingsStrings.accentValue)
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.textPrimary)
            }
            .frame(minHeight: TouchTarget.standard.points)
            .accessibilityElement(children: .combine)
            caption(SettingsStrings.accentDetail)
        }
    }

    /// `NFR-1.9`, which the requirement makes configurable rather than optional.
    private var workout: some View {
        GroupedSection(Text(SettingsStrings.workoutTitle)) {
            Toggle(isOn: binding(\.keepScreenAwake)) {
                Text(SettingsStrings.keepAwakeLabel)
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.textPrimary)
            }
            .tint(ColorToken.brandAccent)
            caption(SettingsStrings.keepAwakeHint)
        }
    }

    /// A label beside a menu that draws only its own selection.
    private func menuRow(
        _ label: LocalizedStringResource, @ViewBuilder control: () -> some View
    ) -> some View {
        HStack {
            Text(label)
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textSecondary)
            Spacer(minLength: Spacing.sm.points)
            control()
        }
        .frame(minHeight: TouchTarget.standard.points)
    }

    /// The sentence under a control.
    private func caption(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A control's binding: read the loaded row, write the row with that one field moved.
    ///
    /// A `Binding` rather than an `onChange`, because a picker's selection *is* the stored value.
    private func binding<Value>(
        _ field: WritableKeyPath<UserSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: field] },
            set: { value in apply { $0[keyPath: field] = value } }
        )
    }

    /// The display steps this row's picker offers.
    private var precisions: [DisplayPrecision] {
        SettingsOptions.displayPrecisions(including: settings.displayPrecision)
    }

    /// The loadable increments this row's picker offers, in the unit being read.
    private var increments: [Weight] {
        SettingsOptions.roundingIncrements(
            for: settings.displayUnit, including: settings.defaultRoundingIncrement)
    }

    /// The lookback windows this row's picker offers.
    private var lookbackWindows: [Int] {
        SettingsOptions.lookbackWindows(including: settings.e1RMLookbackDays)
    }

    /// A display step as the mass it is — "0.25 kg".
    private func stepLabel(_ precision: DisplayPrecision) -> String {
        AppFormat.weightStep(precision, in: settings.displayUnit, locale: locale)
    }

    /// A loadable increment, rendered fine enough that 1.25 kg does not read as 1 kg.
    private func incrementLabel(_ increment: Weight) -> String {
        AppFormat.weight(
            WeightDisplay(unit: settings.displayUnit, precision: .quarter), locale: locale
        )
        .format(increment)
    }
}
