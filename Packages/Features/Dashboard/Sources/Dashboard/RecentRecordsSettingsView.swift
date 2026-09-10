import AppNavigation
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
    ///
    /// **The read runs on every appearance rather than once**, which is what makes the chosen-lift
    /// count on ``RecentRecordsSettingsForm`` true after a visit to the screen it opens: that
    /// picker writes the settings row and pops back here (`FR-17.3.3`, `TR-1.5`).
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg.points) {
                switch RecentRecordsSettingsScreenState.current(state) {
                case .loading:
                    LoadingStateView()
                case .failed:
                    ErrorStateView(
                        message: Text(DashboardStrings.recentRecordsSettingsError),
                        retryEmphasis: .primary,
                        retry: { Task { await state.load() } })
                case .ready(let settings):
                    RecentRecordsSettingsForm(
                        settings: settings,
                        chosenExerciseCount: settings.recentRecordsExerciseIDs?.count ?? 0,
                        schemes: state.schemeChoices,
                        hasFailedWrite: state.writeFailure != nil,
                        apply: { change in Task { await state.apply(change) } },
                        setSchemesChosen: { on in Task { await state.setSchemesChosen(on) } },
                        toggleScheme: { scheme in Task { await state.toggleScheme(scheme) } })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(DashboardStrings.recentRecordsSettingsTitle))
        .task { await state.load() }
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

    /// How many lifts the pushed picker has ticked — the second line of the row that opens it.
    ///
    /// **Read off the stored column rather than off a loaded catalogue**, which is what lets this
    /// screen stop reading the exercises at all: the count is a fact about the row, and the list it
    /// counts belongs to the screen behind ``chooseLifts``.
    let chosenExerciseCount: Int

    /// The schemes in scope, and which are ticked.
    let schemes: [RecentRecordsSchemeChoice]

    /// Whether the last change failed to store. Nothing moved if it did.
    let hasFailedWrite: Bool

    /// Moves one field on the stored row.
    let apply: (@escaping (inout UserSettings) -> Void) -> Void

    /// Switches the schemes between every scheme and a chosen list.
    let setSchemesChosen: (Bool) -> Void

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
        schemeSection
        baselines
    }

    /// `FR-16.3.1`: which exercises the feed reports on, and the way to the list under `.chosen`.
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
            // FR-17.3.3: the sentence is about the option selected, not about the first one.
            caption(DashboardStrings.recentRecordsScopeDetail(for: settings.recentRecordsScope))
            if settings.recentRecordsScope == .chosen { chooseLifts }
        }
    }

    /// `FR-17.3.3`'s row: the count of chosen lifts, and the screen that changes it.
    ///
    /// **A push rather than the inline list T-16.07 shipped**, which is review finding 08: the
    /// catalogue is 132 rows, and unfolding them between the scope picker and the schemes made
    /// every other control on this screen unreachable without a long scroll. T-16.07's argument
    /// against pushing — a row leading to a chooser the current scope ignores is a dead end — is
    /// answered by drawing the row only under `.chosen` rather than by keeping the list inline.
    ///
    /// **Its own link rather than `Settings`' ``SettingsLinkRow``**, because `TR-1.3` keeps the two
    /// feature modules from importing each other and this is the only row of its shape here.
    private var chooseLifts: some View {
        NavigationLink(value: Route.settings(.recentRecordsExercises)) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                    Text(DashboardStrings.recentRecordsExercisesChoose)
                        .font(Typography.body.font)
                        .foregroundStyle(ColorToken.textPrimary)
                    Text(DashboardStrings.recentRecordsExercisesCount(chosenExerciseCount))
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

    /// `FR-17.3.2`: every scheme, or the lifter's own list.
    ///
    /// **Off is the un-configured position and it narrows nothing**, which is the whole of what
    /// `FR-17.3.1` changed here: the toggle used to say **Follow my training** and to mean a
    /// threshold, and a record the workout badged could fail it.
    private var schemeSection: some View {
        GroupedSection(Text(DashboardStrings.recentRecordsSchemesTitle)) {
            Toggle(
                isOn: Binding(
                    get: { settings.recentRecordsSchemes != .everyScheme },
                    set: { setSchemesChosen($0) })
            ) {
                Text(DashboardStrings.recentRecordsSchemesOnlyThese)
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.textPrimary)
            }
            .tint(ColorToken.brandAccent)
            caption(DashboardStrings.recentRecordsSchemesDetail)
            if settings.recentRecordsSchemes != .everyScheme { schemeChoices }
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
