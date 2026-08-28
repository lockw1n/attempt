import AppNavigation
import DerivedValues
import DesignSystem
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// The Settings tab's landing screen (`FR-1.10.1`, `TR-1.2`).
///
/// The view half of the pattern: it holds ``SettingsLandingState`` in `@State`, reads its phase and
/// calls its methods, and contains no logic of its own worth testing. The full preferences surface
/// (`FR-1.10.1`, `FR-1.10.2`) replaces what is shown here.
///
/// **Its copy comes from this module's catalogue** (`G-3.4`), through ``SettingsStrings`` — a
/// string declared in a feature package resolves against that package's bundle rather than the
/// app's, so the module owns its own. The screen's *title* is still the tab's, supplied by the app
/// target: a tab and the screen it opens must not be able to disagree about their name.
public struct SettingsLandingView: View {
    @State private var state: SettingsLandingState

    /// Builds the screen over the repository its state reads and writes through.
    ///
    /// - Parameters:
    ///   - repository: Where the settings row lives.
    ///   - records: The app's one recompute actor, told when the formula moves (`FR-1.7.3`).
    public init(repository: any SettingsRepository, records: PersonalRecordRecomputer) {
        _state = State(
            initialValue: SettingsLandingState(repository: repository, records: records))
    }

    /// The screen's three phases: in flight, loaded, failed.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg.points) {
                switch state.phase {
                case .idle, .loading:
                    ProgressView()
                        .tint(ColorToken.brandAccent)
                case .loaded(let settings):
                    preferences(settings)
                case .failed(let diagnostic):
                    failure(diagnostic)
                }
                equipment
                bodyweight
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .task { await state.load() }
    }

    /// `FR-1.10.3`'s way into the gyms.
    ///
    /// **Outside the phase switch**, and that is not tidiness: the equipment profiles are their own
    /// rows in their own repository, so a preferences read that failed says nothing about whether
    /// they can be shown — putting the link inside `.loaded` would make one failed read take away a
    /// screen that does not depend on it.
    private var equipment: some View {
        GroupedSection(Text(SettingsStrings.equipmentTitle)) {
            link(
                to: .settings(.equipmentProfiles),
                label: SettingsStrings.equipmentRow,
                detail: SettingsStrings.equipmentDetail)
        }
    }

    /// `FR-1.8`'s way into the bodyweight log.
    ///
    /// Outside the phase switch too, and for ``equipment``'s reason: the readings are their own rows
    /// in their own repository, so a preferences read that failed says nothing about whether they
    /// can be shown.
    private var bodyweight: some View {
        GroupedSection(Text(SettingsStrings.bodyweightSectionTitle)) {
            link(
                to: .settings(.bodyweight),
                label: SettingsStrings.bodyweightRow,
                detail: SettingsStrings.bodyweightDetail)
        }
    }

    /// One row that opens another screen: what is behind it, and one line on what is there.
    ///
    /// A `NavigationLink` over a `Route` rather than a closure — the destination is composed by the
    /// app target (`TR-1.3`), and the route is what lets this screen name it without importing it.
    private func link(
        to route: Route, label: LocalizedStringResource, detail: LocalizedStringResource
    ) -> some View {
        NavigationLink(value: route) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                    Text(label)
                        .font(Typography.body.font)
                        .foregroundStyle(ColorToken.textPrimary)
                    Text(detail)
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.textSecondary)
                }
                Spacer(minLength: Spacing.sm.points)
                Image(systemName: "chevron.right")
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// The loaded row: the one preference this task wires end to end, and the rest as read-outs.
    ///
    /// A failed write is reported *above* the controls rather than in place of them: the row is
    /// still loaded and still editable, so replacing the screen with the error would take away the
    /// retry, which is the next tap.
    private func preferences(_ settings: UserSettings) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            if let writeFailure = state.writeFailure {
                diagnosticCard(title: SettingsStrings.writeErrorTitle, detail: writeFailure)
            }

            GroupedSection(Text(SettingsStrings.unitsTitle)) {
                Picker(selection: unitSelection) {
                    ForEach(MassUnit.allCases, id: \.self) { unit in
                        Text(SettingsStrings.unitSymbol(for: unit)).tag(unit)
                    }
                } label: {
                    Text(SettingsStrings.unitsPicker)
                }
                .pickerStyle(.segmented)
            }

            GroupedSection(Text(SettingsStrings.estimatorTitle)) {
                HStack {
                    Text(SettingsStrings.estimatorPicker)
                        .font(Typography.body.font)
                        .foregroundStyle(ColorToken.textSecondary)
                    Spacer(minLength: Spacing.sm.points)
                    Picker(selection: formulaSelection) {
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
                .frame(minHeight: TouchTarget.standard.points)
                Text(SettingsStrings.estimatorDetail)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GroupedSection(Text(SettingsStrings.scaffoldTitle)) {
                row(SettingsStrings.scaffoldAppearance, settings.theme.rawValue)
            }
        }
    }

    /// A read-out pair. The value is a stored identifier rendered as itself — diagnostic output,
    /// not copy, which is why it stays `verbatim` while the label does not.
    private func row(_ label: LocalizedStringResource, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textSecondary)
            Spacer()
            Text(verbatim: value)
                .font(Typography.numericValue.font)
                .foregroundStyle(ColorToken.textPrimary)
        }
    }

    /// The failed phase, and the retry out of it.
    ///
    /// The button is the reason ``SettingsLandingState/Phase/failed(_:)`` is recoverable: `.task`
    /// runs once per view identity, and a screen whose only read failed would otherwise stay
    /// broken for as long as the tab is alive.
    private func failure(_ diagnostic: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md.points) {
            diagnosticCard(title: SettingsStrings.loadErrorTitle, detail: diagnostic)
            Button {
                Task { await state.load() }
            } label: {
                Text(SettingsStrings.loadErrorRetry)
            }
        }
    }

    /// A failure, shown as what it is rather than as a sentence written for the user.
    private func diagnosticCard(title: LocalizedStringResource, detail: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                Text(title)
                    .font(Typography.cardTitle.font)
                    .foregroundStyle(ColorToken.textPrimary)
                Text(verbatim: detail)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
            }
        }
    }

    /// `FR-1.7.2`'s formula, on ``unitSelection``'s shape.
    ///
    /// **A menu rather than a segmented control**, which the unit picker is: six names do not fit
    /// across a phone at any Dynamic Type size, and five of them are surnames a lifter reads rather
    /// than scans.
    private var formulaSelection: Binding<E1RMFormulaID> {
        Binding(
            get: {
                guard case .loaded(let settings) = state.phase else { return .defaultFormula }
                return settings.e1RMFormula
            },
            set: { formula in
                Task { await state.setE1RMFormula(formula) }
            }
        )
    }

    /// The picker's binding: reads the loaded row, writes through the state's one mutation.
    ///
    /// A `Binding` rather than an `onChange`, because a segmented control's selection *is* the
    /// stored value — and the write is asynchronous, so the set has to start a task rather than
    /// assign.
    private var unitSelection: Binding<MassUnit> {
        Binding(
            get: {
                guard case .loaded(let settings) = state.phase else { return .kilograms }
                return settings.displayUnit
            },
            set: { unit in
                Task { await state.setDisplayUnit(unit) }
            }
        )
    }
}
