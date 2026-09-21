#if os(iOS)

    import DesignSystem
    import DesignTokens
    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SwiftUI

    @testable import Logging

    // TR-1.12's day fixtures, split out of `WeekSnapshotTests.swift` at SwiftLint's file ceiling
    // (T-18.22, which added `DOD-18.15`'s two-group row). A separate file rather than a shorter
    // set: `PastDaySnapshotTests` builds its own rows out of these, so the two screens that draw a
    // day draw the same fixtures — `FR-17.7.6` held in the references as well as in the code.

    /// The days these references render (`FR-17.9`).
    ///
    /// EVERY ROW'S TRAILING MENU DRAWS AS A PLACEHOLDER, on this package's standing `ImageRenderer`
    /// note: a `Menu` is UIKit-backed. The **frame is honoured** — 44 × 60 pt, which is what these
    /// references measure the row's height against — so only the glyph is substituted, and the
    /// circle beside it renders for real. Read the yellow block as *a control of that size is here*,
    /// not as a defect, and do not replace it with an `Image` to make the picture prettier: a
    /// fixture that is not the screen is evidence about the fixture (T-16.17).
    enum DayFixtures {
        /// Two rows nobody has answered, both with a load and therefore both with a circle.
        static var notStarted: [DayRow] {
            [
                row("Back Squat", plan: planned(140_000)),
                row("Romanian Deadlift", plan: planned(100_000)),
            ]
        }

        /// The one-line answer.
        static var asPlanned: DayRow {
            row("Back Squat", plan: planned(140_000), performed: planned(140_000), answer: .logged)
        }

        /// The two-line answer — one set short, at a lighter load, and a record all the same.
        ///
        /// **The badge is pictured here rather than on the as-planned row**, so one reference shows
        /// the mark and the other shows the line without it: a set below the plan can still be the
        /// heaviest ever done at that scheme, which is the case worth a picture (`FR-1.6.3`).
        static var deviated: DayRow {
            row(
                "Bench Press",
                plan: planned(100_000),
                performed: [target(95_000, reps: 5, sets: 4)],
                answer: .logged,
                records: [
                    [SchemeMark(scheme: RecordScheme(reps: 5, sets: 4), isFirstPerformance: false)]
                ])
        }

        /// `DOD-18.15`'s row, which is the author's own screenshot: two planned groups, the second
        /// a rep short, and **both** groups holding a record (`FR-18.3.6`, `FR-18.3.8`).
        ///
        /// **The one fixture that can see `F-22`.** Every other answered row here performs one run,
        /// and a row of one run carries one badge whether the rule is per group or per exercise —
        /// so the defect was invisible to all of them. Both marks are first performances, which is
        /// also the pair that reads worst when only one is drawn: the row claimed `10 × 3` was a
        /// first and said nothing about `7 × 3`, which was equally one.
        static var twoGroupRecords: DayRow {
            row(
                "Back Squat",
                plan: [target(57_000, reps: 10, sets: 3), target(64_000, reps: 8, sets: 3)],
                performed: [target(57_000, reps: 10, sets: 3), target(64_000, reps: 7, sets: 3)],
                answer: .logged,
                records: [
                    [SchemeMark(scheme: RecordScheme(reps: 10, sets: 3), isFirstPerformance: true)],
                    [SchemeMark(scheme: RecordScheme(reps: 7, sets: 3), isFirstPerformance: true)],
                ])
        }

        /// `FR-17.9.6`'s skip.
        static var skipped: DayRow {
            row("Barbell Row", plan: planned(80_000), answer: .skipped)
        }

        /// `FR-15.2.2`'s blank target.
        static var openLoad: DayRow {
            row("Ab Wheel", plan: [target(nil, reps: 12, sets: 3)])
        }

        /// `FR-1.2.2`'s added row: no plan at all.
        static var added: DayRow {
            row("Face Pull", plan: [])
        }

        /// `FR-15.2.2`'s open load, answered — the row whose two lines render to different widths.
        static var openLoadLogged: DayRow {
            row(
                "Ab Wheel",
                plan: [target(nil, reps: 12, sets: 3)],
                performed: [target(24_000, reps: 12, sets: 3)],
                answer: .logged)
        }

        /// The longest name the catalogue holds (`T-18.05`'s revision 4), which is what `NFR-18.2`
        /// is measured against.
        ///
        /// **In the fixture's English slot rather than its Ukrainian one**, because these
        /// references render `en_US_POSIX` — what is being pictured is a width, and the width is
        /// the string's.
        static let longName = "Жим у важільному тренажері на похилій лаві"

        /// `FR-15.2.1`'s two groups, which no Phase 1.7 fixture had.
        static var twoGroups: [WeekPlanTarget] {
            [target(110_000, reps: 4, sets: 4), target(100_000, reps: 8, sets: 2)]
        }

        /// The longest name over a two-group plan, unanswered and answered (`FR-18.3.1`,
        /// `FR-18.3.2`).
        ///
        /// **The second row deviated rather than as planned**, so the reference carries the case
        /// that draws the column twice: two labels, four numbers, and one edge they all line up on.
        static var longNameTwoGroups: [DayRow] {
            [
                row(longName, plan: twoGroups),
                row(
                    "Dumbbell Fly",
                    plan: [target(12_000, reps: 12, sets: 3), target(14_000, reps: 10, sets: 3)],
                    performed: [target(12_000, reps: 12, sets: 3), target(14_000, reps: 8, sets: 3)],
                    answer: .logged),
            ]
        }

        /// The day's rows, as the screen draws them.
        ///
        /// - Parameter rows: The rows.
        /// - Returns: The section.
        static func section(_ rows: [DayRow]) -> some View {
            DayChecklistSection(
                rows: rows,
                progress: DayProgress(rows),
                unit: .kilograms,
                answer: { _ in },
                log: { _ in },
                skip: { _ in })
        }

        /// One row, over the week fixture's own catalogue row so the two files name one lift once.
        private static func row(
            _ name: String,
            plan: [WeekPlanTarget],
            performed: [WeekPlanTarget] = [],
            answer: DayRowAnswer = .unanswered,
            records: [[SchemeMark]] = []
        ) -> DayRow {
            DayRow(
                id: UUID(),
                exercise: WeekFixtures.line(name, grams: nil).exercise,
                plan: plan,
                performed: performed,
                answer: answer,
                records: records)
        }

        /// The fixture's standard prescription: five sets of five.
        private static func planned(_ grams: Int) -> [WeekPlanTarget] {
            [target(grams, reps: 5, sets: 5)]
        }

        /// One target group.
        private static func target(_ grams: Int?, reps: Int, sets: Int) -> WeekPlanTarget {
            WeekPlanTarget(
                id: UUID(), weight: grams.map { Weight(grams: $0) }, reps: reps, sets: sets)
        }
    }

#endif
