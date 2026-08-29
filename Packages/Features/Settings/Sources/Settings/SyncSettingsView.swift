import AppNavigation
import DesignSystem
import Localization
import RepositoryInterface
import SwiftUI

/// Whether this device mirrors to iCloud, how far it has got, and the switch (`FR-1.12.1`–
/// `FR-1.12.3`).
///
/// The view half of this module's pattern: it holds ``SyncSettingsState`` in `@State`, follows it,
/// and hands everything drawable to ``SyncSettingsReading`` so a reference can be rendered without
/// a control behind it.
public struct SyncSettingsView: View {
    @State private var state: SyncSettingsState

    /// The calendar the last-synced time is named in — see ``SyncSettingsReading``.
    @Environment(\.calendar) private var calendar

    /// The locale it is written in.
    @Environment(\.locale) private var locale

    /// Builds the screen over the sync it reports on.
    ///
    /// - Parameter control: Sync, as `FR-1.12.1`–`FR-1.12.3` need it.
    public init(control: any SyncControl) {
        _state = State(initialValue: SyncSettingsState(control: control))
    }

    /// The switch, the status and what turning it off does.
    public var body: some View {
        ScrollView {
            SyncSettingsReading(
                state: SyncScreenState.current(state.status),
                isEnabled: state.isEnabled,
                needsRestart: state.needsRestart,
                lastSucceededAt: state.status.lastSucceededAt,
                calendar: calendar,
                locale: locale,
                setEnabled: { enabled in Task { await state.setEnabled(enabled) } }
            )
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(SettingsStrings.syncTitle))
        // ONE `.task`, NOT A LOAD PLUS AN OBSERVE. `follow()` reads the switch and then holds the
        // status stream open for as long as the screen is alive, which is what a status that moves
        // on its own needs — unlike HealthAccessView, nothing here has to be re-read on a
        // foreground, because the events arrive whether this screen is looking or not.
        .task { await state.follow() }
    }
}

/// The sync screen with no control behind it — every state, as values (`TR-1.12`).
///
/// **The calendar and locale are parameters rather than environment reads**, which is this repo's
/// standing snapshot finding rather than a new one: `Date.FormatStyle` renders against the device's
/// own zone whatever is around it, so a reference recorded through the ambient calendar encodes the
/// recorder's time zone and fails everywhere else.
struct SyncSettingsReading: View {
    /// Which state to draw.
    let state: SyncScreenState

    /// Whether the switch is shown on.
    let isEnabled: Bool

    /// Whether the choice and the running store disagree, so a restart is owed.
    let needsRestart: Bool

    /// When sync last worked, or `nil` if it never has.
    let lastSucceededAt: Date?

    /// The calendar the time is named in.
    let calendar: Calendar

    /// The locale it is written in.
    let locale: Locale

    /// What the switch does.
    let setEnabled: (Bool) -> Void

    /// The switch's own value.
    ///
    /// **`@State` plus `onChange` rather than `Binding(get:set:)`, and that is a compiler bug
    /// rather than a style.** `Binding`'s setter is `@isolated(any) @Sendable`, so a closure
    /// property converted into one is rejected under this package's strict flags — and spelling the
    /// property `@MainActor` to satisfy that CRASHES swiftc 6.3.3 during IRGen for the
    /// reabstraction thunk (`SmallVector unable to grow`, requested capacity 2^32+1). Measured,
    /// twice. A binding straight off `@State` needs no thunk, so no conversion happens at all.
    ///
    /// It also gives the switch the optimism it wants independently: the control moves under the
    /// finger, and ``isEnabled`` correcting it afterwards is what the second `onChange` is for.
    @State private var switchValue: Bool

    /// Builds the reading.
    ///
    /// Written out because ``switchValue`` seeds from ``isEnabled``, which a memberwise initializer
    /// cannot express.
    ///
    /// - Parameters:
    ///   - state: Which state to draw.
    ///   - isEnabled: Whether the switch is shown on.
    ///   - needsRestart: Whether a restart is owed.
    ///   - lastSucceededAt: When sync last worked.
    ///   - calendar: The calendar the time is named in.
    ///   - locale: The locale it is written in.
    ///   - setEnabled: What the switch does.
    init(
        state: SyncScreenState,
        isEnabled: Bool,
        needsRestart: Bool,
        lastSucceededAt: Date?,
        calendar: Calendar,
        locale: Locale,
        setEnabled: @escaping (Bool) -> Void
    ) {
        self.state = state
        self.isEnabled = isEnabled
        self.needsRestart = needsRestart
        self.lastSucceededAt = lastSucceededAt
        self.calendar = calendar
        self.locale = locale
        self.setEnabled = setEnabled
        _switchValue = State(initialValue: isEnabled)
    }

    /// The switch, then the status, then the paragraph the switch needs.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            toggle
            status
            explanation
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `FR-1.12.3`'s switch.
    ///
    /// **Disabled while the store is re-opening**, because that is the one moment a second tap
    /// would ask for the opposite of what is already in flight.
    private var toggle: some View {
        GroupedSection(Text(SettingsStrings.syncTitle)) {
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                Toggle(isOn: $switchValue) {
                    Text(SettingsStrings.syncToggle)
                }
                .onChange(of: switchValue) { _, chosen in
                    guard chosen != isEnabled else { return }
                    setEnabled(chosen)
                }
                // The correction half: a switch that moved and then failed to take goes back.
                .onChange(of: isEnabled) { _, settled in switchValue = settled }
                Text(SettingsStrings.syncToggleDetail)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // The gap between the switch and the store, said out loud. Drawn under the toggle
                // rather than beside the status, because it is a fact about the control that was
                // just touched and not about what sync is doing.
                if needsRestart {
                    Text(isEnabled ? SettingsStrings.syncRestartOn : SettingsStrings.syncRestartOff)
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// `FR-1.12.2`: where sync has got to, and when it last worked.
    private var status: some View {
        GroupedSection(Text(SettingsStrings.syncStatusTitle)) {
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                Text(statusLine)
                    .font(Typography.body.font)
                    .foregroundStyle(state == .failed ? ColorToken.negative : ColorToken.textPrimary)
                // THE LAST GOOD TIME IS DRAWN UNDER A FAILURE TOO, which is the point of keeping it:
                // "could not sync — last synced 09:12" is a far smaller thing to read than "could
                // not sync" alone, and it is the half a lifter can act on.
                if state != .off {
                    Text(lastSyncedLine)
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.textSecondary)
                }
                if state == .failed {
                    Text(SettingsStrings.syncStatusFailedDetail)
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    /// `FR-1.12.3`'s promise, drawn whether the switch is on or off.
    ///
    /// **Before the switch is thrown rather than after**, because the fear a control like this
    /// raises is that turning it off deletes something — and an explanation that only appeared once
    /// it was off would arrive after the moment it was needed.
    private var explanation: some View {
        Text(SettingsStrings.syncOffDetail)
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The status, in the reader's words.
    private var statusLine: LocalizedStringResource {
        switch state {
        case .off: SettingsStrings.syncStatusOff
        case .idle: SettingsStrings.syncStatusIdle
        case .active(.setup): SettingsStrings.syncStatusSetup
        case .active(.download): SettingsStrings.syncStatusDownload
        case .active(.upload): SettingsStrings.syncStatusUpload
        case .failed: SettingsStrings.syncStatusFailed
        }
    }

    /// When sync last worked, or that it never has.
    ///
    /// **"Not synced yet" is not a failure**, and is drawn in the same place a time would be: a
    /// device that has just been switched on has nothing to report, and an empty line there would
    /// read as something missing.
    private var lastSyncedLine: LocalizedStringResource {
        guard let lastSucceededAt else { return SettingsStrings.syncLastNever }
        let formatted = lastSucceededAt.formatted(
            AppFormat.resolved(AppFormat.dateAndTime(locale: locale), in: calendar))
        return SettingsStrings.syncLastSynced(formatted)
    }
}
