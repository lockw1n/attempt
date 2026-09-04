#if os(iOS)

    import DesignSystem
    import Foundation
    import PowerliftingCore
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Logging

    // TR-1.12 for `FR-1.2.10`'s strip. A file of its own on `SessionSnapshotFixtures`' argument:
    // the suite beside this one is already at `file_length`, and the two grow for different reasons.
    // The session note's own references moved out with `FR-16.6.1`, to the suite that pictures the
    // foot of the screen it is now folded into.
    //
    // The subject takes values rather than a store, so it needs none of the `.task` `ImageRenderer`
    // cannot run — see the other suite's header for what these references can and cannot show.

    @MainActor
    @Suite("Previous-session snapshots")
    struct SessionNoteSnapshotTests {
        // MARK: - The previous session (FR-1.2.10)

        @Test func previousSession() throws {
            // FR-1.2.10's strip. Two things a picture settles: the warmup in the fixture is not
            // drawn — only the work is compared — and the three sets stay one wrapping line at
            // accessibility3 rather than becoming three.
            try assertSnapshots(named: "Session-previous") {
                fixedEnvironment {
                    PreviousPerformanceStrip(
                        state: .performed(Fixtures.previousPerformance), unit: .kilograms)
                }
            }
        }

        @Test func previousSessionNeverTrained() throws {
            // The first time an exercise is logged: FR-1.13.3's state rather than a blank area,
            // which is what FR-1.2.10 asked for. The third state — nothing has looked yet — draws
            // nothing at all and has no reference, deliberately: an empty picture is not evidence.
            try assertSnapshots(named: "Session-previous-none") {
                fixedEnvironment {
                    PreviousPerformanceStrip(state: .noneYet, unit: .kilograms)
                }
            }
        }
    }

#endif
