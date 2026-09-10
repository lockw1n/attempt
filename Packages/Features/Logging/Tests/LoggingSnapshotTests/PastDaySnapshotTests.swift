#if os(iOS)

    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Logging

    // TR-1.12 for `history.session` in the shape `FR-17.7.6` gave it — a past planned day, split
    // from `PastSessionSnapshotTests.swift` at SwiftLint's file ceiling. That file pictures the
    // free workout's card and the screen's own states; this one pictures the day.
    //
    // WHAT THESE REFERENCES ARE FOR IS THE DIFFERENCE, WHICH IS WHAT IS MISSING. `DayChecklistSection`
    // is the Train tab's own section, already pictured by `WeekSnapshotTests`; here it is drawn with
    // `answer` and `skip` absent, so an unanswered row carries no circle and the menu offers no
    // **Skip** — those are how a day is answered, and this one has been.

    @Suite("Past day snapshots")
    struct PastDaySnapshotTests {
        // MARK: - A past planned day (FR-17.7.6)

        @Test func pastDayRows() throws {
            // What read-only means, and the picture is the only place it is visible: two rows
            // NOBODY answered — the state `Day-not-started` draws with a circle on each — and here
            // there is none, because a circle is how a day is answered and this day is over
            // (`FR-17.7.5`). The menu keeps **Log** and loses **Skip**.
            try assertSnapshots(named: "Past-day-rows") {
                fixedEnvironment { PastFixtures.day(DayFixtures.notStarted) }
            }
        }

        @Test func pastDaySkipped() throws {
            // `DOD-17.8`'s History half: three exercises done and one skipped, the skipped row
            // reading **Skipped** and the heading counting it among the answered. The middle row
            // also carries `FR-17.7.4`'s note, which `DayExerciseRow` draws under the *Did* line
            // and which no other reference in this package pictures.
            try assertSnapshots(named: "Past-day-skipped") {
                fixedEnvironment {
                    PastFixtures.day(PastFixtures.threeDoneOneSkipped)
                }
            }
        }

        @Test func pastDayAdherence() throws {
            // `FR-17.7.3` and `FR-17.7.6`: the day's program position and its adherence, on the
            // line under the title where the active session draws the same two facts. The date is
            // NOT here — it is the navigation title, and drawing it twice is what this line was
            // split off to avoid.
            try assertSnapshots(named: "Past-day-adherence") {
                fixedEnvironment {
                    SessionSummaryLine(
                        session: PastFixtures.programDay,
                        adherence: SessionAdherence(PastFixtures.plannedExercises))
                }
            }
        }
    }

    extension PastFixtures {
        /// `DOD-17.8`'s day: three exercises answered and one of them skipped.
        ///
        /// **The middle row carries `FR-17.7.4`'s note**, which is the only place a day's row can
        /// draw one — there are no member rows here and nothing collapses, so a note that is not on
        /// this line is on no line at all. On the deviated row rather than a fresh one, so the
        /// picture also settles the order: the *Did* line, then the note under it, then the badge.
        static var threeDoneOneSkipped: [DayRow] {
            [DayFixtures.asPlanned, noted(DayFixtures.deviated), DayFixtures.skipped]
        }

        /// `row` with a per-set note on it (`FR-17.7.4`, `FR-1.2.3`).
        ///
        /// - Parameter row: The row.
        /// - Returns: The same row, annotated.
        static func noted(_ row: DayRow) -> DayRow {
            DayRow(
                id: row.id,
                exercise: row.exercise,
                plan: row.plan,
                performed: row.performed,
                answer: row.answer,
                notes: [kneeNote],
                records: row.records)
        }

        /// One of ``plannedExercises``' five sets — the last a rep short of what was prescribed.
        ///
        /// - Parameters:
        ///   - entryID: The exercise it belongs to.
        ///   - order: Its place among that exercise's sets.
        /// - Returns: The set.
        static func performed(entryID: UUID, order: Int) -> SetEntry {
            set(entryID: entryID, order: order, grams: 100_000, reps: order == 4 ? 3 : 5)
        }

        /// A day of a program, three weeks in — what `FR-17.7.6`'s summary line reads its position
        /// off.
        static var programDay: WorkoutSession {
            WorkoutSession(
                id: UUID(),
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                date: stamp,
                startedAt: stamp,
                endedAt: stamp.addingTimeInterval(4200),
                notes: "",
                bodyweight: nil,
                programRunID: UUID(),
                scheduledWorkoutID: nil,
                weekNumber: 3,
                dayIndex: 0
            )
        }

        /// A planned exercise four sets of whose five were performed as prescribed — the numerator
        /// and the denominator ``pastDayAdherence`` pictures.
        static var plannedExercises: [SessionExercise] {
            let entryID = UUID()
            let planned = PlannedTargetGroup(
                id: UUID(),
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                exerciseEntryID: entryID,
                order: 0,
                targetWeight: Weight(grams: 100_000),
                targetReps: 5,
                targetSets: 5
            )
            return [
                SessionExercise(
                    entry: entry(id: entryID),
                    exercise: catalogueRow,
                    sets: (0..<5).map { performed(entryID: entryID, order: $0) },
                    planned: [planned]
                )
            ]
        }

        /// A past day's rows, exactly as ``PastSessionView/dayRows`` composes them — read-only,
        /// which is `answer` and `skip` being absent.
        ///
        /// - Parameter rows: The rows.
        /// - Returns: The section.
        static func day(_ rows: [DayRow]) -> some View {
            DayChecklistSection(
                rows: rows,
                progress: DayProgress(rows),
                unit: .kilograms,
                log: { _ in })
        }
    }

#endif
