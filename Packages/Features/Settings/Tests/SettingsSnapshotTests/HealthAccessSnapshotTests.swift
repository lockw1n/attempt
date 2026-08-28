#if os(iOS)

    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Settings

    // TR-1.12 for FR-1.10.4. The reading rather than the screen, on the bodyweight suite's terms:
    // the screen is a `.task` over a health source, and a reference through it is a reference of a
    // spinner.
    //
    // NO `NavigationStack` AROUND THESE, which is this repo's standing finding rather than a new
    // one — see the same paragraph in Logging's and ExerciseLibrary's suites. The not-asked state
    // carries a `NavigationLink`, so a stack looks like the right thing and renders an EMPTY IMAGE
    // instead: `ImageRenderer` draws none of a UIKit-backed container's content. Measured here too,
    // by recording twenty blank references before this comment existed. What the references
    // therefore show is the link DIMMER than the app draws it — a `NavigationLink` with no stack
    // above it renders as though it led nowhere. The simulator run is what says it is live.
    //
    // THE COPY IS THE SUBJECT HERE. This screen has no data — every state is a sentence, and the
    // sentence that must never say "granted" is the one these references pin.

    @MainActor
    @Suite("Health access snapshots")
    struct HealthAccessSnapshotTests {
        @Test func notAsked() throws {
            // Nothing has been asked, so there is nothing to change: the next tap is the import,
            // and there is deliberately no Open Health button — this app is not in Health's list
            // of apps until it has asked once.
            try assertSnapshots(named: "Health-access-not-asked") {
                HealthAccessReading(state: .notAsked, retry: {})
            }
        }

        @Test func answered() throws {
            // The question has been put and answered, and the app is not told which way. The
            // status reads "Requested", the disclaimer under it says why that is as far as it
            // goes, and the path into Health is written out because Health has no deeper link.
            try assertSnapshots(named: "Health-access-answered") {
                HealthAccessReading(state: .answered, retry: {})
            }
        }

        @Test func unavailable() throws {
            // FR-1.13.1's empty state: no health data on this device, so no access to hold. Only
            // a restored route reaches this — the Settings row is drawn away.
            try assertSnapshots(named: "Health-access-unavailable") {
                HealthAccessReading(state: .unavailable, retry: {})
            }
        }

        @Test func unknown() throws {
            // FR-1.13.1's error state. It is a real HealthKit answer rather than a thrown error,
            // and the retry is offered because the next read may well say something.
            try assertSnapshots(named: "Health-access-unknown") {
                HealthAccessReading(state: .unknown, retry: {})
            }
        }

        @Test func loading() throws {
            // The one read here is out of process, so this wait is real — the case
            // LoadingStateView's own doc comment says the component exists for.
            try assertSnapshots(named: "Health-access-loading") {
                HealthAccessReading(state: .loading, retry: {})
            }
        }
    }

#endif
