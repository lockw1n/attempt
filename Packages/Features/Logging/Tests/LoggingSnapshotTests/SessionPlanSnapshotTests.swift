#if os(iOS)

    import DesignSystem
    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Logging

    // TR-1.12 for FR-15.3's additions to the workout in progress, in a suite of its own because
    // `SessionSnapshotTests.swift` had reached `file_length`. The conventions are that file's — four
    // configurations per reference, the real copy, data through `AppFormat`.

    @MainActor
    @Suite("Planned-vs-actual snapshots")
    struct SessionPlanSnapshotTests {
        // MARK: - Planned vs actual (FR-15.3.1, FR-15.3.2, FR-15.3.4)

        @Test func plannedCards() throws {
            // The four shapes the plan puts on a card, in one picture: a target beside each logged
            // set, a deviation mark where the set missed it, the blank-weight target's third state
            // — which is the one a "deviation of zero" would silently swallow — the **Planned
            // next** section with its one-tap command, and the check-off in both of its words.
            //
            // The whole reason this is a reference rather than an assertion: G-4.5 says a deviation
            // cannot be carried by colour alone, and whether the arrow and the sign are actually
            // drawn beside the magnitude is a claim only a picture settles. The accessibility3
            // configuration is the other half — the row was already spending its width on two 44pt
            // controls and the load before this line existed.
            try assertSnapshots(named: "Session-planned-cards") {
                fixedEnvironment {
                    SessionExerciseList(
                        exercises: PlanFixtures.exercises,
                        expansion: .constant(PlanFixtures.expansion),
                        warmupExpansion: .constant([:]),
                        move: { _, _ in },
                        unit: .kilograms,
                        previous: PreviousPerformances(),
                        personalRecords: SessionRecordMarks(),
                        logSet: { _ in },
                        mark: { _, _ in },
                        markCompleted: { _, _ in },
                        edit: { _ in },
                        markDone: { _, _ in },
                        logPlanned: { _ in }
                    )
                }
            }
        }
    }

#endif
