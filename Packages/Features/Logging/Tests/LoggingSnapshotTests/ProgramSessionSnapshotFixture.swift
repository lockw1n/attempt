#if os(iOS)

    import Foundation
    import RepositoryInterface

    @testable import Logging

    // The one fixture `FR-16.8.3`'s references need, in a file of its own because
    // `SessionSnapshotFixtures`' own enum is at `type_body_length` — the same reason that file
    // exists apart from the suites it serves.

    extension Fixtures {
        /// ``session``'s workout, started from week 2 day 1 of a program (`FR-16.8.3`).
        ///
        /// **A second fixture rather than two columns on the first.** Every reference already
        /// recorded over ``session`` is a workout started outside a program, which is the commoner
        /// case and the one those references are for; stamping the shared fixture would re-record
        /// all of them to assert something only two of them are about.
        static let programSession = WorkoutSession(
            id: UUID(uuidString: "0F5A1E24-9B7D-4C31-8E62-0000000000A2") ?? UUID(),
            createdAt: startedAt,
            updatedAt: startedAt,
            deletedAt: nil,
            date: day,
            startedAt: startedAt,
            endedAt: nil,
            notes: "",
            bodyweight: nil,
            programRunID: UUID(uuidString: "0F5A1E24-9B7D-4C31-8E62-0000000000A3") ?? UUID(),
            scheduledWorkoutID: nil,
            weekNumber: 2,
            dayIndex: 0
        )
    }

#endif
