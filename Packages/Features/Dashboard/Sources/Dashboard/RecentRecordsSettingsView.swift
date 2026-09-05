import DerivedValues
import DesignSystem
import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// Which of the configuration screen's three states is current (`FR-1.13.1`).
///
/// No insufficient-data state and no empty one: the screen configures a preference rather than
/// reporting a derived value, and a lifter with no records at all still has a scope to set. Where
/// the *scheme* list is empty that is a caption under a control, not a state of the screen.
enum RecentRecordsSettingsScreenState: Equatable {
    /// The first read has not answered yet.
    case loading

    /// It answered with the row.
    case ready(UserSettings)

    /// It could not be read; a retry may work.
    case failed

    /// Which state a load is in. The failure outranks a row already on screen, on the feed's rule.
    ///
    /// - Parameter state: The screen's load.
    /// - Returns: The state to draw.
    static func current(_ state: RecentRecordsSettingsState) -> Self {
        if state.failure != nil { return .failed }
        guard state.hasLoaded, let settings = state.settings else { return .loading }
        return .ready(settings)
    }
}

/// `FR-16.3`'s configuration: which lifts, which schemes, and whether baselines show.
///
/// **A `Dashboard` screen behind a `Settings` route**, which is the shape `FR-1.10.3`'s gyms already
/// have in the other direction: `TR-1.3` keeps the two feature modules from depending on each other,
/// and the app target — which owns both — is where the route meets the screen. It lives here rather
/// than in `Settings` because it configures this module's feed and reuses this module's picker row
/// and its default-lifts rule.
///
/// The `ScrollView`/`VStack` shape every screen in this app uses rather than a `List`, for
/// `TR-1.12`'s reason: the snapshot harness renders through `ImageRenderer`, which draws a
/// placeholder for anything UIKit-backed.
public struct RecentRecordsSettingsView: View {
    /// The screen's own state.
    @State private var state: RecentRecordsSettingsState

    /// The locale the exercise names are resolved in (`FR-1.14.2`), handed to the state before its
    /// read.
    @Environment(\.locale) private var locale

    /// Builds the screen.
    ///
    /// - Parameters:
    ///   - settings: Where the configuration is stored.
    ///   - catalogue: The exercises the chosen scope names.
    ///   - records: The app's one recompute actor.
    public init(
        settings: any SettingsRepository,
        catalogue: any ExerciseRepository,
        records: PersonalRecordRecomputer
    ) {
        _state = State(
            initialValue: RecentRecordsSettingsState(
                settings: settings, catalogue: catalogue, records: records))
    }

    /// The three states, and the read that fills them.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg.points) {
                switch RecentRecordsSettingsScreenState.current(state) {
                case .loading:
                    LoadingStateView()
                case .failed:
                    ErrorStateView(
                        message: Text(DashboardStrings.recentRecordsSettingsError),
                        retry: { Task { await state.load() } })
                case .ready(let settings):
                    RecentRecordsSettingsForm(
                        settings: settings,
                        exercises: state.exerciseChoices,
                        schemes: state.schemeChoices,
                        hasFailedWrite: state.writeFailure != nil,
                        apply: { change in Task { await state.apply(change) } },
                        toggleExercise: { id in Task { await state.toggleExercise(id) } },
                        setSchemesDerived: { on in Task { await state.setSchemesDerived(on) } },
                        toggleScheme: { scheme in Task { await state.toggleScheme(scheme) } })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(DashboardStrings.recentRecordsSettingsTitle))
        .task {
            state.nameLanguage = ExerciseNameLanguage(locale)
            await state.load()
        }
    }
}

/// What the configuration draws, with no store behind it — `TR-1.12`'s renderable half.
///
/// A pure function of the row and the two lists, on `SettingsPreferencesForm`'s rule: each control
/// mutates its own copy of the row and hands the whole thing back, so a control cannot clear a
/// column it never read.
struct RecentRecordsSettingsForm: View {
    /// The row every control reads its selection from.
    let settings: UserSettings

    /// The exercises the chosen scope can name.
    let exercises: [TiledExerciseChoice]

    /// The schemes in scope, and which are ticked.
    let schemes: [RecentRecordsSchemeChoice]

    /// Whether the last change failed to store. Nothing moved if it did.
    let hasFailedWrite: Bool

    /// Moves one field on the stored row.
    let apply: (@escaping (inout UserSettings) -> Void) -> Void

    /// Adds or removes one exercise from the chosen list.
    let toggleExercise: (UUID) -> Void

    /// Switches the schemes between derived and chosen.
    let setSchemesDerived: (Bool) -> Void

    /// Adds or removes one scheme from the chosen list.
    let toggleScheme: (RecordScheme) -> Void

    /// The three sections, in the order a reader narrows the feed: which lifts, which schemes, and
    /// then the one flag that is about neither.
    var body: some View {
        if hasFailedWrite {
            // No retry closure: nothing was stored and the controls are unchanged, so trying again
            // is the same tap on the same control.
            ErrorStateView(message: Text(DashboardStrings.recentRecordsSettingsWriteError))
        }
        scope
        if settings.recentRecordsScope == .chosen { chosenExercises }
        schemeSection
        baselines
    }

    /// `FR-16.3.1`: which exercises the feed reports on.
    private var scope: some View {
        GroupedSection(Text(DashboardStrings.recentRecordsScopeTitle)) {
            Picker(selection: binding(\.recentRecordsScope)) {
                ForEach(RecentRecordsScope.allCases, id: \.self) { scope in
                    Text(DashboardStrings.recentRecordsScopeName(for: scope)).tag(scope)
                }
            } label: {
                Text(DashboardStrings.recentRecordsScopeTitle)
            }
            .pickerStyle(.segmented)
            caption(DashboardStrings.recentRecordsScopeDetail)
        }
    }

    /// The `.chosen` scope's own list — revealed by the picker above rather than pushed.
    ///
    /// **Inline rather than a screen of its own**, unlike `FR-1.9.1`'s tile picker: this list is
    /// meaningful only under one of three scopes, and a row leading to a chooser that the current
    /// scope ignores is the dead end `SettingsLandingView` hides the Health row to avoid.
    private var chosenExercises: some View {
        GroupedSection(Text(DashboardStrings.recentRecordsExercisesTitle)) {
            if exercises.isEmpty {
                EmptyStateView(headline: Text(DashboardStrings.recentRecordsExercisesEmpty))
            } else {
                ForEach(exercises) { choice in
                    TiledExerciseRow(choice: choice, toggle: toggleExercise)
                }
            }
        }
    }

    /// `FR-16.3.2`: derived from the log, or the lifter's own list.
    private var schemeSection: some View {
        GroupedSection(Text(DashboardStrings.recentRecordsSchemesTitle)) {
            Toggle(
                isOn: Binding(
                    get: { settings.recentRecordsSchemes == .derived },
                    set: { setSchemesDerived($0) })
            ) {
                Text(DashboardStrings.recentRecordsSchemesDerived)
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.textPrimary)
            }
            .tint(ColorToken.brandAccent)
            caption(DashboardStrings.recentRecordsSchemesDetail)
            if settings.recentRecordsSchemes != .derived { schemeChoices }
        }
    }

    /// The cells the scope's records carry, ticked where chosen.
    @ViewBuilder private var schemeChoices: some View {
        if schemes.isEmpty {
            caption(DashboardStrings.recentRecordsSchemesEmpty)
        } else {
            ForEach(schemes) { choice in
                Toggle(
                    isOn: Binding(
                        get: { choice.isChosen }, set: { _ in toggleScheme(choice.scheme) })
                ) {
                    Text(
                        DashboardStrings.recentRecordsScheme(
                            choice.scheme.reps, choice.scheme.sets)
                    )
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.textPrimary)
                }
                .tint(ColorToken.brandAccent)
                .frame(minHeight: TouchTarget.standard.points)
            }
        }
    }

    /// `FR-16.3.4`: the one flag that narrows neither the lifts nor the schemes.
    private var baselines: some View {
        GroupedSection(Text(DashboardStrings.recentRecordsBaselinesTitle)) {
            Toggle(isOn: binding(\.recentRecordsShowsBaselines)) {
                Text(DashboardStrings.recentRecordsBaselinesLabel)
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.textPrimary)
            }
            .tint(ColorToken.brandAccent)
            caption(DashboardStrings.recentRecordsBaselinesDetail)
        }
    }

    /// The sentence under a control.
    private func caption(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A control's binding: read the loaded row, write the row with that one field moved.
    private func binding<Value>(
        _ field: WritableKeyPath<UserSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: field] },
            set: { value in apply { $0[keyPath: field] = value } }
        )
    }
}
