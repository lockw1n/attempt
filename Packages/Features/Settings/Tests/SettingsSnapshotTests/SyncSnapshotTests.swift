#if os(iOS)

    import Foundation
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Settings

    // TR-1.12 for FR-1.12.1-FR-1.12.3. The reading rather than the screen, on this module's terms:
    // the screen is a `.task` over a status stream, and a reference through it is a reference of
    // whatever had arrived when the renderer looked.
    //
    // NO `NavigationStack` AROUND THESE — this repo's standing finding, written out in the health
    // suite: `ImageRenderer` draws none of a UIKit-backed container's content, so a stack renders an
    // empty image.
    //
    // THE SWITCH ITSELF IS NOT PINNED BY THESE REFERENCES, and that is a renderer limit rather
    // than an oversight. `ImageRenderer` cannot draw a UIKit-backed `UISwitch`, so every reference
    // here shows the same yellow placeholder in the toggle's place whatever `isEnabled` is — the
    // on and off references are identical in that rectangle. Measured by reading Sync-failed
    // (enabled) beside Sync-awaiting-restart (disabled). It is the same class of artifact as the
    // `NavigationLink` one the health suite records.
    //
    // WHAT FOLLOWS FROM THAT: these tests cannot fail if the toggle's binding inverts, so the
    // simulator run is the only thing standing behind FR-1.12.3's control. What they DO pin is the
    // copy and the status line — which is where this screen's real risk is, since G-5.3 turns on
    // the app not saying something untrue about itself.
    //
    // THE CALENDAR AND LOCALE ARE PASSED IN, NOT READ FROM THE ENVIRONMENT. `Date.FormatStyle`
    // renders against the device's own zone whatever is around it, so a last-synced time recorded
    // through the ambient calendar encodes the recorder's time zone and fails everywhere else.
    // Fixed here for the same reason the restore suite fixes it.

    @MainActor
    @Suite("Sync snapshots")
    struct SyncSnapshotTests {
        /// The instant every state here reports as its last success.
        private static let lastSynced = Date(timeIntervalSince1970: 1_767_257_520)

        /// The calendar every state here is drawn in.
        private static var gmt: Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
            return calendar
        }

        private func reading(
            _ state: SyncScreenState,
            isEnabled: Bool,
            needsRestart: Bool = false,
            lastSucceededAt: Date? = SyncSnapshotTests.lastSynced
        ) -> some View {
            SyncSettingsReading(
                state: state,
                isEnabled: isEnabled,
                needsRestart: needsRestart,
                lastSucceededAt: lastSucceededAt,
                calendar: SyncSnapshotTests.gmt,
                locale: Locale(identifier: "en_GB"),
                setEnabled: { _ in })
        }

        @Test func idle() throws {
            // On, nothing moving, and a time behind it. The ordinary state.
            try assertSnapshots(named: "Sync-idle") {
                reading(.idle, isEnabled: true)
            }
        }

        @Test func neverSynced() throws {
            // FR-1.13.1's empty state, and it is the STATUS LINE rather than a second line under
            // one: nothing has come back from the account, so there is nothing to be up to date
            // with, and a device that said both would contradict itself in two consecutive lines.
            // "Not synced yet" is not a failure and must not read as one — a device switched on a
            // minute ago has nothing to report.
            try assertSnapshots(named: "Sync-never-synced") {
                reading(.idle, isEnabled: true, lastSucceededAt: nil)
            }
        }

        @Test func loading() throws {
            // FR-1.13.1's loading state, and the reason this screen has one at all: every value
            // this view takes starts at what a switched-off device would report, so a frame drawn
            // before the read lands says "Off" on a device that is mirroring. T-1.09's component,
            // with no message — the wait is one hop onto an actor.
            //
            // WHAT THIS REFERENCE PINS IS AN ABSENCE, and it is worth saying so rather than letting
            // a near-empty image read as a broken test. `LoadingStateView` draws a spinner, which is
            // UIKit-backed, so `ImageRenderer` leaves the same yellow placeholder here that it
            // leaves in the toggle's place above — the spinner itself is not pinned by anything.
            // What IS pinned is that the switch, the status and the paragraph are all absent, which
            // is the whole claim: this screen must not say "Off" before it has read anything.
            try assertSnapshots(named: "Sync-loading") {
                reading(.loading, isEnabled: false)
            }
        }

        @Test func checkingAccount() throws {
            // Setup is NOT a transfer: it is the account and zone check that runs once per launch,
            // and a screen that said "syncing" here would report movement where none is happening.
            try assertSnapshots(named: "Sync-setup") {
                reading(.active(.setup), isEnabled: true)
            }
        }

        @Test func uploading() throws {
            // The other direction, pinned because the two are one enum case apart and the copy is
            // the only thing that distinguishes them on screen.
            try assertSnapshots(named: "Sync-uploading") {
                reading(.active(.upload), isEnabled: true)
            }
        }

        @Test func downloading() throws {
            // Records arriving. The status line moves; nothing else on the screen does.
            try assertSnapshots(named: "Sync-downloading") {
                reading(.active(.download), isEnabled: true)
            }
        }

        @Test func failed() throws {
            // THE LAST GOOD TIME IS STILL DRAWN, which is the point of keeping it through a
            // failure: "could not sync - last synced 1 Jan 2026 at 08:52" is a far smaller thing to
            // read than the first half alone. G-3.4: the error itself is nowhere on this screen.
            try assertSnapshots(named: "Sync-failed") {
                reading(.failed, isEnabled: true)
            }
        }

        @Test func off() throws {
            // FR-1.12.3. No status line under the heading, because a device that is not syncing has
            // no last-synced time worth reporting - and the paragraph promising nothing was deleted
            // is drawn whether the switch is on or off.
            try assertSnapshots(named: "Sync-off") {
                reading(.off, isEnabled: false)
            }
        }

        @Test func awaitingRestart() throws {
            // The switch has been thrown and the store has not moved: `cloudKitDatabase` is fixed
            // when the container is built. This reference is the one that pins the app not lying
            // about its own state (G-5.3) - the toggle reads off, the status still reads what this
            // launch is doing, and the sentence between them says why.
            try assertSnapshots(named: "Sync-awaiting-restart") {
                reading(.idle, isEnabled: false, needsRestart: true)
            }
        }
    }

#endif
