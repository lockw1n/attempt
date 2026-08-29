import Foundation
import RepositoryInterface

/// What the sync screen knows (`FR-1.12.1`–`FR-1.12.3`).
///
/// **A screen's state rather than one of `TR-1.2`'s stores**, on ``HealthAccessState``'s rule: it is
/// read from this screen alone and lives exactly as long as it does. The status it reports outlives
/// the screen, but it lives in the ``SyncControl`` below rather than here.
///
/// **The switch moves at once and the store does not.** `ModelConfiguration.cloudKitDatabase` is
/// fixed when the container is built, so the choice is recorded now and applied at the next launch
/// — see ``SyncControl``. ``needsRestart`` is that gap, and the screen draws it rather than
/// pretending the switch did something it did not.
@Observable
final class SyncSettingsState {
    /// Whether the switch is shown on — the lifter's choice.
    private(set) var isEnabled = false

    /// What this launch is actually doing, which the choice above outruns until the next start.
    private(set) var isRunning = false

    /// Where sync has got to.
    private(set) var status = SyncStatus.off

    /// Whether the choice and the running store disagree, so a restart is owed (`FR-1.12.3`).
    var needsRestart: Bool { isEnabled != isRunning }

    /// The sync this screen reports on and switches.
    @ObservationIgnored private let control: any SyncControl

    /// Builds the state over the control it reports on.
    ///
    /// - Parameter control: Sync, as `FR-1.12.1`–`FR-1.12.3` need it.
    init(control: any SyncControl) {
        self.control = control
    }

    /// Reads the switch and the status once, then follows the status until the caller stops.
    ///
    /// **One call rather than a load and an observe**, because the stream's first element is the
    /// status in force: a separate read would either duplicate it or race it.
    func follow() async {
        isEnabled = await control.isEnabled
        isRunning = await control.isRunning
        for await status in control.statusUpdates() {
            self.status = status
        }
    }

    /// Records the lifter's choice (`FR-1.12.3`).
    ///
    /// **It does not touch the log**, and neither does anything it calls — see ``SyncControl``.
    /// What it changes today is the preference and this screen; what changes at the next launch is
    /// whether the container mirrors.
    ///
    /// - Parameter enabled: What the lifter chose.
    func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        await control.setEnabled(enabled)
    }
}

/// Which of the screen's states to draw — ``SyncStatus`` and ``SyncSettingsState/Phase`` folded
/// into one axis.
///
/// The same split ``HealthAccessScreenState`` makes, and for the same reason: a snapshot reference
/// can be rendered over one of these with no control behind it.
enum SyncScreenState: Equatable, CaseIterable {
    /// Switched off by the lifter (`FR-1.12.3`).
    case off

    /// On, nothing in flight.
    case idle

    /// On, with an attempt running.
    case active(SyncActivity)

    /// On, and the last finished attempt failed.
    case failed

    /// Every state, which `CaseIterable` cannot synthesize past an associated value.
    static var allCases: [SyncScreenState] {
        [.off, .idle, .failed] + SyncActivity.allCases.map(Self.active)
    }

    /// Which state the screen is in.
    ///
    /// - Parameter status: Where sync has got to.
    /// - Returns: The state to draw.
    static func current(_ status: SyncStatus) -> Self {
        switch status.phase {
        case .off: .off
        case .idle: .idle
        case .active(let activity): .active(activity)
        case .failed: .failed
        }
    }
}
