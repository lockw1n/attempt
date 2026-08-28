import AppNavigation
import DesignSystem
import SwiftUI

/// What Health access this app has, and the one lever there is over it (`FR-1.10.4`).
///
/// **The screen exists because the prompt cannot be raised twice.** A person who refused the first
/// import cannot be asked again from inside the app — iOS shows the sheet once — so the only honest
/// surface is one that says where the request has got to and sends them to the place the switch
/// actually lives. A "grant access" button here would do nothing, visibly.
///
/// The view half of the pattern: it holds ``HealthAccessState`` in `@State`, reads it, owns the way
/// out to Health, and hands everything drawable to ``HealthAccessReading`` so a reference can be
/// rendered without a source.
public struct HealthAccessView: View {
    @State private var state: HealthAccessState

    /// Whether the last attempt to open Health was refused.
    ///
    /// **A command that does nothing and says nothing is the failure this screen was written to
    /// avoid**, so the open is not fire-and-forget — see ``openHealth()``.
    @State private var openFailed = false

    /// Whether this app is in the foreground: the switch this screen points at is thrown in another.
    @Environment(\.scenePhase) private var scenePhase

    /// Where the switch is, when the viewer's own app can reach it.
    @Environment(\.openURL) private var openURL

    /// Builds the screen over the source it reports on.
    ///
    /// - Parameter health: `FR-1.8.2`'s sample source. `nil` draws the unavailable state.
    public init(health: (any BodyweightSampleSource)? = nil) {
        _state = State(initialValue: HealthAccessState(health: health))
    }

    /// The status, and whatever this screen can offer beside it.
    public var body: some View {
        ScrollView {
            HealthAccessReading(
                state: HealthAccessScreenState.current(state.phase),
                openFailed: openFailed,
                retry: { Task { await state.load() } },
                openHealth: openHealth
            )
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(SettingsStrings.healthTitle))
        .task { await state.load() }
        // THE STATUS MOVES WHILE THIS SCREEN IS ALIVE AND NOT LOOKING, and `.task` runs once per
        // view identity. The prompt is raised by the import the not-asked state links to, which
        // comes back by a POP; the switch is thrown in Health, which comes back by a FOREGROUND.
        // Neither rebuilds this screen, so one trigger each — and neither draws the wait over a
        // status that is already on screen, which is `refresh()` rather than `load()`.
        .onAppear { Task { await state.refresh() } }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await state.refresh() }
        }
    }

    /// Opens Health, where the per-app read switch lives.
    ///
    /// **No fallback to this app's own page under Settings**: measured, the health switches are not
    /// there, so landing someone on it would be the silent no-op this screen was written to avoid.
    ///
    /// **The refusal is read rather than assumed away.** `HKHealthStore.isHealthDataAvailable()`
    /// says whether this device stores health data, not whether anything will handle Health's URL,
    /// so ``HealthAccessScreenState/unavailable`` does not cover every device this can fail on.
    /// `openURL`'s completion is what says it failed, and ``openFailed`` is what draws it.
    private func openHealth() {
        guard let url = Self.healthApp else {
            openFailed = true
            return
        }
        openURL(url) { accepted in
            openFailed = !accepted
        }
    }

    /// The Health app's own root. The switch is inside it, at the path
    /// ``SettingsStrings/healthChangePath`` spells out — Health publishes no deeper link.
    static let healthApp = URL(string: "x-apple-health://")
}

/// What the Health-access screen draws, with no source behind it — `TR-1.12`'s renderable half.
///
/// No `ScrollView` here, the other screens' reason: `ImageRenderer` draws none of one's content.
struct HealthAccessReading: View {
    /// Which state to draw.
    let state: HealthAccessScreenState

    /// Whether the last attempt to open Health was refused, drawn beside the command.
    let openFailed: Bool

    /// What the error state's retry does.
    let retry: () -> Void

    /// What the Health command does.
    let openHealth: () -> Void

    /// One of the five, and nothing layered over it: this screen holds no list a diagnostic could
    /// sit above, so every state here replaces the last.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            switch state {
            case .loading:
                LoadingStateView()
            case .unavailable:
                EmptyStateView(
                    symbolName: "heart.slash",
                    headline: Text(SettingsStrings.healthUnavailableHeadline),
                    message: Text(SettingsStrings.healthUnavailableMessage)
                )
            case .unknown:
                ErrorStateView(
                    headline: Text(SettingsStrings.healthUnknownHeadline),
                    message: Text(SettingsStrings.healthUnknownMessage),
                    retry: retry
                )
            case .notAsked:
                status(SettingsStrings.healthStatusNotAsked)
                notAsked
            case .answered:
                status(SettingsStrings.healthStatusAnswered)
                answered
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The status itself: one word for where the request has got to, and the sentence that stops it
    /// being read as a grant.
    ///
    /// **The disclaimer is beside every determined status and not only the answered one.** It is the
    /// fact this whole screen exists to state, and a reader who sees it once on the state they are
    /// not in has not seen it.
    private func status(_ value: LocalizedStringResource) -> some View {
        GroupedSection(Text(SettingsStrings.healthStatusTitle)) {
            VStack(alignment: .leading, spacing: Spacing.xs.points) {
                Text(value)
                    .font(Typography.cardTitle.font)
                    .foregroundStyle(ColorToken.textPrimary)
                Text(SettingsStrings.healthDisclosureDetail)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// Nobody has been asked yet — so there is nothing to change, and the next tap is the import
    /// that raises the prompt (`TR-1.9`).
    ///
    /// **No Health button here**, deliberately: an app that has never asked is not in Health's own
    /// list of apps, so the link would land on a page that does not mention this one.
    private var notAsked: some View {
        GroupedSection(Text(SettingsStrings.healthPromptTitle)) {
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                Text(SettingsStrings.healthPromptDetail)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textSecondary)
                SettingsLinkRow(
                    route: .settings(.bodyweight),
                    label: SettingsStrings.bodyweightRow,
                    detail: SettingsStrings.healthPromptRowDetail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The question has been answered, so the switch exists — and it is in Health, not here.
    ///
    /// **The path is written out beside the button.** Opening Health lands on Summary; the switch is
    /// several taps further in, and a command that drops someone somewhere they then have to search
    /// is barely better than no command.
    private var answered: some View {
        GroupedSection(Text(SettingsStrings.healthChangeTitle)) {
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                Button(action: openHealth) { Text(SettingsStrings.healthOpenAction) }
                Text(SettingsStrings.healthChangePath)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textSecondary)
                // A refusal in the form this module's other refusals take. The command stays: it
                // may well work on the next tap, and removing it would leave the screen with no
                // way out at all.
                if openFailed {
                    Text(SettingsStrings.healthOpenFailed)
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.negative)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
