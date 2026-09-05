#if os(iOS)

    import DesignSystem
    import DesignTokens
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Logging

    // TR-1.12 for FR-16.8.2's card on Train, in the same four configurations as every other
    // reference here. All four of `ProgramNextUp.Day` are drawn, because each is a different
    // screen: one has two commands under it, one is FR-16.8.4's offer, and two are FR-1.13.1
    // states with nothing to start.

    @MainActor
    @Suite("Program card snapshots")
    struct ProgramNextUpSnapshotTests {
        /// The ordinary case, and `NFR-15.3`'s first tap: **Start** filled, **Skip day** under it.
        @Test func nextDay() throws {
            try assertSnapshots(named: "TrainNextUp-day") {
                card(.next(index: 1, routineID: UUID(), name: "Bench and accessories"))
            }
        }

        /// `FR-16.8.4`'s offer. The message is three claims in one paragraph — where next week's
        /// loads come from, that they stay editable, and what happens to this week's routines — so
        /// `accessibility3` is the configuration worth reading.
        @Test func weekComplete() throws {
            try assertSnapshots(named: "TrainNextUp-week-complete") {
                card(.weekComplete)
            }
        }

        /// `FR-15.2.5`'s archive reaching a program day: the day is returned intact and this is
        /// where it is answered, with **Skip day** as the way past.
        @Test func archivedRoutine() throws {
            try assertSnapshots(named: "TrainNextUp-archived") {
                card(.archivedRoutine(index: 0))
            }
        }

        /// A program in force with nothing in it — `FR-1.13.1`'s empty state on this card.
        @Test func noDays() throws {
            try assertSnapshots(named: "TrainNextUp-no-days") {
                card(.noDays)
            }
        }

        /// The card over one reading, with every command inert.
        private func card(_ day: ProgramNextUp.Day) -> some View {
            ProgramNextUpCard(
                nextUp: ProgramNextUp(
                    runID: UUID(), programName: "Course #2", weekNumber: 3, day: day),
                start: { _, _ in },
                skip: { _ in },
                startNextWeek: {})
        }
    }

#endif
