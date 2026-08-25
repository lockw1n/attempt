#if os(iOS)

    import DesignSystem
    import Foundation
    import PowerliftingCore
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Logging

    // TR-1.12 for T-1.27's two surfaces. A file of its own on `SessionSnapshotFixtures`' argument:
    // the suite beside this one is already at `file_length`, and the two grow for different reasons.
    //
    // Both subjects take values rather than a store, so neither needs the `.task` `ImageRenderer`
    // cannot run — see the other suite's header for what these references can and cannot show.

    @MainActor
    @Suite("Session note and previous-session snapshots")
    struct SessionNoteSnapshotTests {
        // MARK: - Session notes and the previous session (FR-1.2.9, FR-1.2.10)

        @Test func sessionNotes() throws {
            // FR-1.2.9 as a workout that has been noted and saved: heading, field, and no commands.
            // The field itself is a `TextField` and rasterises as the renderer's placeholder, the
            // same way the date and warmup controls above do — what this compares is the heading,
            // the field's height at three-to-ten lines, and the absence of the two commands.
            try assertSnapshots(named: "Session-notes") {
                fixedEnvironment {
                    SessionNotesSection(
                        draft: .constant(Fixtures.storedNote), hasFailed: false, save: {})
                }
            }
        }

        @Test func sessionNotesUnsavedAndFailed() throws {
            // The other shape: an edit that has not been stored puts **Save note** and **Discard
            // changes** on screen, and a write that failed puts the shared error under them. Both
            // in one reference because neither moves the other — the failure renders beneath the
            // commands and the commands are there either way — and because what is worth checking
            // is that all three still fit at accessibility3, where `ViewThatFits` drops the two
            // commands into a column.
            try assertSnapshots(named: "Session-notes-editing") {
                fixedEnvironment {
                    SessionNotesSection(
                        draft: .constant(Fixtures.editedNote), hasFailed: true, save: {})
                }
            }
        }

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
