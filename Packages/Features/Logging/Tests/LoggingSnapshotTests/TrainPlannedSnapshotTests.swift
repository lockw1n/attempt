#if os(iOS)

    import DesignSystem
    import Foundation
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Logging

    // FR-16.6.5 for Train's card over a workout that has not been performed yet. A file of its own
    // on `SessionAboveFoldSnapshotTests`' argument: the two suites beside it are at `file_length`
    // already, and this one carries a fixture the others have no use for.

    @MainActor
    @Suite("Train's card over a planned workout")
    struct TrainPlannedSnapshotTests {
        @Test func plannedWorkout() throws {
            // The same card `Train-in-progress` renders, over a workout dated ahead of today: it
            // says **Planned**, which is the word the history row already uses for it. Its own
            // reference because the heading is the only thing that differs — and a heading claiming
            // a lifter is mid-workout when they are not is exactly what a picture settles.
            try assertSnapshots(named: "Train-planned") {
                fixedEnvironment {
                    SessionInProgressSection(session: Self.plannedSession, lifecycle: .planned)
                }
            }
        }

        /// A workout dated ahead of its own training day, and never started (`FR-16.4.3`).
        ///
        /// **`startedAt` is `nil`, and that is not incidental**: a planned workout has not been
        /// begun, so a card drawing "Started 6:42 PM" over the word **Planned** would picture a
        /// contradiction. The section draws that row only where there is a start time; this is the
        /// fixture that lets the reference say so.
        private static let plannedSession = WorkoutSession(
            id: UUID(uuidString: "0F5A1E24-9B7D-4C31-8E62-0000000000A2") ?? UUID(),
            createdAt: Fixtures.session.createdAt,
            updatedAt: Fixtures.session.updatedAt,
            deletedAt: nil,
            date: Fixtures.session.date,
            startedAt: nil,
            endedAt: nil,
            notes: "",
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil
        )
    }

#endif
