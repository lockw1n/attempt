import AppNavigation
import DerivedValues
import DesignSystem
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// The Settings tab's landing screen (`FR-1.10.1`, `FR-1.10.2`, `TR-1.2`).
///
/// The view half of the pattern: it holds ``SettingsLandingState`` in `@State`, reads its phase and
/// calls its methods, and contains no logic of its own worth testing. The preferences themselves
/// are ``SettingsPreferencesForm``, which is a pure function of the loaded row.
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
    ///   - records: The app's one recompute actor, told when the formula or the window moves
    ///     (`FR-1.7.3`, `FR-1.7.1`).
    ///   - preferencesDidChange: What the app runs once a preference held elsewhere lands — the
    ///     theme (`FR-1.10.2`) and the screen-wake (`NFR-1.9`).
    public init(
        repository: any SettingsRepository,
        records: PersonalRecordRecomputer,
        preferencesDidChange: @escaping (UserSettings) -> Void = { _ in }
    ) {
        _state = State(
            initialValue: SettingsLandingState(
                repository: repository,
                records: records,
                preferencesDidChange: preferencesDidChange))
    }

    /// The screen's three phases: in flight, loaded, failed.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg.points) {
                switch state.phase {
                case .idle, .loading:
                    // FR-1.13.1's shared component (T-1.09), not a local spinner — this screen
                    // predates it and this is where the last of its states converges.
                    LoadingStateView()
                case .loaded(let settings):
                    SettingsPreferencesForm(
                        settings: settings,
                        writeFailure: state.writeFailure,
                        apply: { change in Task { await state.apply(change) } })
                case .failed:
                    failure
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

    /// The failed phase, and the retry out of it — `FR-1.13.1`'s shared component (`T-1.09`).
    ///
    /// The button is the reason ``SettingsLandingState/Phase/failed(_:)`` is recoverable: `.task`
    /// runs once per view identity, and a screen whose only read failed would otherwise stay
    /// broken for as long as the tab is alive. The phase's diagnostic is deliberately not drawn:
    /// it is a diagnostic and not a sentence written for the user (`G-3.4`).
    private var failure: some View {
        ErrorStateView(
            headline: Text(SettingsStrings.loadErrorTitle),
            message: Text(SettingsStrings.loadErrorMessage),
            retry: { Task { await state.load() } })
    }
}
