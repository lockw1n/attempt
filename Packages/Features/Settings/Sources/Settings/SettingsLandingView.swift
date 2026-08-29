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

    /// Whether this device has a health source at all — the one thing this screen asks of it.
    ///
    /// A `Bool` read once at construction rather than the source itself: `FR-1.10.4`'s screen is
    /// what reports on Health, and all the landing decides is whether a row leading there is
    /// honest. `false` draws it away rather than dimming it, `T-1.51`'s rule for the same fact.
    private let isHealthAvailable: Bool

    /// Builds the screen over the repository its state reads and writes through.
    ///
    /// - Parameters:
    ///   - repository: Where the settings row lives.
    ///   - records: The app's one recompute actor, told when the formula or the window moves
    ///     (`FR-1.7.3`, `FR-1.7.1`).
    ///   - health: `FR-1.8.2`'s sample source, which decides only whether `FR-1.10.4`'s row is
    ///     drawn. `nil`, or a source this device does not have, leaves it off.
    ///   - preferencesDidChange: What the app runs once a preference held elsewhere lands — the
    ///     theme (`FR-1.10.2`) and the screen-wake (`NFR-1.9`).
    public init(
        repository: any SettingsRepository,
        records: PersonalRecordRecomputer,
        health: (any BodyweightSampleSource)? = nil,
        preferencesDidChange: @escaping (UserSettings) -> Void = { _ in }
    ) {
        isHealthAvailable = health?.isAvailable == true
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
                data
                about
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
            SettingsLinkRow(
                route: .settings(.equipmentProfiles),
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
            VStack(alignment: .leading, spacing: Spacing.md.points) {
                SettingsLinkRow(
                    route: .settings(.bodyweight),
                    label: SettingsStrings.bodyweightRow,
                    detail: SettingsStrings.bodyweightDetail)
                // FR-1.10.4, beside the log it governs. Absent rather than disabled where this
                // device has no Health — a row opening a screen that could only say "not on this
                // device" is the dead end T-1.51 hid the import command to avoid.
                if isHealthAvailable {
                    SettingsLinkRow(
                        route: .settings(.healthAccess),
                        label: SettingsStrings.healthRow,
                        detail: SettingsStrings.healthRowDetail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Where the lifter's own data goes — `FR-1.11`'s three files, then `FR-1.12`'s iCloud.
    ///
    /// **The fourth row is not a file**, and it sits with the three because the section is about
    /// where the log can end up rather than about the mechanism: three ways it leaves this device
    /// on purpose, and one that keeps it on the lifter's other devices.
    ///
    /// Outside the phase switch, for ``equipment``'s reason: the log lives in its own tables, so a
    /// preferences read that failed says nothing about whether it can be exported — or, for the
    /// last row, about a container and a preference it never touches. **Above About**, because
    /// everything above this point is about the lifter and About is the one section that is about
    /// the app.
    private var data: some View {
        GroupedSection(Text(SettingsStrings.dataSectionTitle)) {
            VStack(alignment: .leading, spacing: Spacing.md.points) {
                SettingsLinkRow(
                    route: .settings(.dataExport),
                    label: SettingsStrings.dataExportRow,
                    detail: SettingsStrings.dataExportDetail)
                // FR-1.11.3, below the export rather than above it: an export is the file a lifter
                // reaches for on purpose, and a backup is the one they take because they should.
                SettingsLinkRow(
                    route: .settings(.backup),
                    label: SettingsStrings.backupRow,
                    detail: SettingsStrings.backupDetail)
                // FR-1.11.4, last of the three: the two rows above hand a file out, and this one
                // reads a file back — the only one of them that can lose anything.
                SettingsLinkRow(
                    route: .settings(.restore),
                    label: SettingsStrings.restoreRow,
                    detail: SettingsStrings.restoreDetail)
                // FR-1.12.1, last of the four and outside the phase switch's concern for the same
                // reason About is: whether this device mirrors is a fact about the container and a
                // preference, so a failed read of the settings row says nothing about it.
                SettingsLinkRow(
                    route: .settings(.sync),
                    label: SettingsStrings.syncRow,
                    detail: SettingsStrings.syncRowDetail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// `FR-1.10.5`'s way into About.
    ///
    /// Outside the phase switch, for ``equipment``'s reason and a stronger one: the version, the
    /// acknowledgements and the privacy policy are facts about the binary rather than rows in any
    /// store, so nothing this screen reads can make them unavailable. **Last**, because it is the
    /// only section here that is about the app rather than about the lifter.
    private var about: some View {
        GroupedSection(Text(SettingsStrings.aboutSectionTitle)) {
            SettingsLinkRow(
                route: .settings(.about),
                label: SettingsStrings.aboutRow,
                detail: SettingsStrings.aboutDetail)
        }
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
