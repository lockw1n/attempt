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
/// **Its copy is `verbatim` scaffolding.** A string declared in a feature package resolves against
/// that package's bundle rather than the app's catalogue (`G-3.4`), and which bundle a feature's
/// copy is resolved against is not settled yet — text written before it is settled would be
/// translated into the wrong one. The screen's title is the tab's, supplied by the app target, for
/// the same reason.
public struct SettingsLandingView: View {
    @State private var state: SettingsLandingState

    /// Builds the screen over the repository its state reads and writes through.
    public init(repository: any SettingsRepository) {
        _state = State(initialValue: SettingsLandingState(repository: repository))
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .task { await state.load() }
    }

    /// The loaded row: the one preference this task wires end to end, and the rest as read-outs.
    private func preferences(_ settings: UserSettings) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            GroupedSection(Text(verbatim: "Units")) {
                Picker(selection: unitSelection) {
                    ForEach(MassUnit.allCases, id: \.self) { unit in
                        Text(verbatim: unit == .kilograms ? "kg" : "lb").tag(unit)
                    }
                } label: {
                    Text(verbatim: "Display unit")
                }
                .pickerStyle(.segmented)
            }

            GroupedSection(Text(verbatim: "Not built yet")) {
                row("Estimator", settings.e1RMFormula.rawValue)
                row("Appearance", settings.theme.rawValue)
            }
        }
    }

    /// A read-out pair. Scaffolding, like the copy it lays out.
    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(verbatim: label)
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textSecondary)
            Spacer()
            Text(verbatim: value)
                .font(Typography.numericValue.font)
                .foregroundStyle(ColorToken.textPrimary)
        }
    }

    /// The failed phase. The diagnostic is shown as what it is rather than as a sentence.
    private func failure(_ diagnostic: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                Text(verbatim: "Settings unavailable")
                    .font(Typography.cardTitle.font)
                    .foregroundStyle(ColorToken.textPrimary)
                Text(verbatim: diagnostic)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
            }
        }
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
