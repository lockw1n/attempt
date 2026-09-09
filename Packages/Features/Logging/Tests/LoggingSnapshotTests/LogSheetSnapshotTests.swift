#if os(iOS)

    import DesignSystem
    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Logging

    // TR-1.12 for `FR-17.1`'s Log sheet, in a suite of its own because `SessionSnapshotTests.swift`
    // had reached `file_length`. The conventions are that file's — four configurations per
    // reference, the real copy, and the sheet composed rather than rendered, since `ImageRenderer`
    // lays a `ScrollView`'s content out and draws none of it.

    @MainActor
    @Suite("Log sheet snapshots")
    struct LogSheetSnapshotTests {
        // MARK: - The form (FR-17.9.4)

        @Test func prefilledFromThePlan() throws {
            // The commonest state by far: **Log** on an unanswered row, opened on the plan's own
            // numbers. The Planned / Actual pair therefore agrees with itself, which is the case
            // the deviation sentence has to say "as planned" for rather than drawing a signed zero.
            try assertSnapshots(named: "Log-sheet-planned") {
                fixedEnvironment { LogSheetFixtures.sheet(over: LogSheetFixtures.unanswered) }
            }
        }

        @Test func theDifferenceIsCalledOut() throws {
            // DOD-17.7's own case: a plan of 30 × 10 × 3 answered with 30 × 8 × 3. The claim a
            // picture settles is that the difference is *stated* — `−2 reps` beside what was done,
            // rather than left for the reader to subtract.
            try assertSnapshots(named: "Log-sheet-deviation") {
                fixedEnvironment {
                    LogSheetFixtures.sheet(over: LogSheetFixtures.deviating)
                }
            }
        }

        @Test func thePerSetFoldOpens() throws {
            // The fold is the whole reason `80 × 8, 8, 6` can be logged as one answer, and every
            // control in it is per set — so the reference is over three of them.
            try assertSnapshots(named: "Log-sheet-per-set") {
                fixedEnvironment { LogSheetFixtures.sheet(over: LogSheetFixtures.perSet) }
            }
        }

        @Test func reopenedOverAnAnsweredRow() throws {
            // FR-17.7.5: the only way to change an answer. Every field is the stored answer's
            // rather than the plan's — 32.5 kg × 8 × 2 against a plan of 30 × 10 × 3 — so the pair
            // deviates on all three dimensions at once, and the fold stays closed because the two
            // stored sets agree and the form above it can say them both.
            try assertSnapshots(named: "Log-sheet-edit") {
                fixedEnvironment { LogSheetFixtures.sheet(over: LogSheetFixtures.answered) }
            }
        }

        // MARK: - FR-17.1.6's opening height, as a number

        @Test func weightAndRepsOpenAboveTheCommands() throws {
            // FR-17.1.6 asserted on the rendering's own height rather than by eye, on
            // `theFirstSetRowIsInsideTheFirstScreen`'s pattern.
            //
            // THE BUDGET. The smallest device this app supports is 375 × 667 pt and this sheet
            // opens `.large`, so it gets the screen less the status bar. Nothing is subtracted for
            // a navigation bar or a tab bar: a sheet covers both.
            //
            // WHAT IS MEASURED, AND WHY IT IS EXACTLY THE REQUIREMENT. The two regions the sheet
            // stacks in this mode, each rendered as the sheet draws it: `SetEditorHead` — which
            // holds the heading, Weight and Reps and nothing else — and the pinned commands. Sets
            // and the plate row scroll and are not counted, which is `FR-17.1.6`'s own wording: it
            // names Weight and Reps. The pinned plan line is not counted because a checklist row
            // does not draw one — its reference is `PlannedActualPair`, inside the scroll view.
            //
            // THIS IS WHAT PUT THE SHEET AT `.large`. Measured with the plate row still between
            // Weight and Reps the head was 447 pt and the total 648.5 — inside 667 only by the
            // status bar, and over it the moment a label wrapped. Moving that row below the fold
            // brings the head to 352.5 and the total to 554.
            //
            // WHAT IS SUBTRACTED. `Snapshot.render` pads every subject by `Spacing.lg` on all four
            // sides and the sheet does not, so the vertical 32 pt per region is the harness's. The
            // horizontal padding is left where it is, which keeps this conservative: the content is
            // rendered 32 pt narrower than the device would, so more labels wrap here than there.
            let budget = SetEditorSheet.smallestScreen - 20.0
            let regions: [(String, AnyView)] = [
                ("head", AnyView(LogSheetFixtures.head(over: LogSheetFixtures.unanswered))),
                ("commands", AnyView(LogSheetFixtures.commands)),
            ]
            var points = 0.0
            for (name, region) in regions {
                let rendered = try Snapshot.render(
                    fixedEnvironment { region }, appearance: .light, typeSize: .default)
                let height = Double(rendered.height) / Snapshot.scale - 2 * Spacing.lg.points
                print("FR-17.1.6 region \(name): \(height) pt")
                points += height
            }
            print("FR-17.1.6 Log sheet opening height: \(points) pt against a \(budget) pt budget")
            #expect(points < budget)
        }

        // MARK: - Fixtures

        /// The Log sheet's regions, in the order and with the paddings the sheet gives them.
        ///
        /// **Composed rather than rendered as ``SetEditorSheet``**, for `SessionPlanSnapshotTests`'
        /// own reason: `ImageRenderer` lays a `ScrollView`'s content out and draws none of it, so a
        /// picture of the sheet is a picture of the commands with the whole form missing. The order
        /// and the spacing are copied from the sheet rather than chosen here.
        ///
        /// **And no pinned plan line, because a checklist row draws none** (T-16.17's family, which
        /// is how these four references were wrong first time round). `SetEditorSheet` draws that
        /// line from ``SessionExercise/nextPlannedGroup``, which is `nil` before the day has a
        /// session and `nil` again once the row's planned sets are all logged — so it was absent
        /// on the first **Log** of every day and on every reopen of an answered row, which is
        /// exactly the pair of states these fixtures picture. The reference in this mode is
        /// ``PlannedActualPair``, which is derived from the row's whole plan and cannot vanish.
        enum LogSheetFixtures {
            /// The locale the form's numbers are read and rendered in — fixed, like every other
            /// input to a reference.
            static let numberLocale = Locale(identifier: "en_US_POSIX")

            /// DOD-17.7's prescription: three sets of ten at 30 kg.
            static let plan: [WeekPlanTarget] = [
                WeekPlanTarget(id: identifier(1), weight: Weight(grams: 30_000), reps: 10, sets: 3)
            ]

            /// **Log** on a row nobody has answered — prefilled from the plan.
            static var unanswered: SetDraft {
                SetDraft(
                    answering: SetEditorRow(plan: plan), unit: .kilograms, locale: Self.numberLocale)
            }

            /// The same form with the reps brought down to eight — DOD-17.7's answer.
            static var deviating: SetDraft {
                var draft = unanswered
                draft.repsText = "8"
                return draft
            }

            /// The fold open over three sets.
            static var perSet: SetDraft {
                var draft = deviating.openingDetails()
                draft.details[2].repsText = "6"
                return draft
            }

            /// The sheet reopened over a row already answered — two sets of eight at 32.5 kg
            /// against a plan of three tens at 30 (`FR-17.7.5`).
            ///
            /// **Deliberately not `8, 8, 6` at the planned load**, which is what ``perSet`` already
            /// holds: recorded that way the two references came out byte-identical, two pictures of
            /// one claim (T-16.02's family, found by `shasum`). What this one has to show is the
            /// half `perSet` cannot — the form prefilled from **what is stored** rather than from
            /// the plan, with the fold *closed* because the stored sets agree with each other, and
            /// a deviation on all three dimensions at once.
            static var answered: SetDraft {
                SetDraft(
                    answering: SetEditorRow(plan: plan, logged: logged),
                    unit: .kilograms,
                    locale: Self.numberLocale)
            }

            /// Two stored sets that agree with each other, at a load the plan did not name.
            static let logged: [SetEntry] = [8, 8].enumerated().map { index, reps in
                SetEntry(
                    id: identifier(10 + index),
                    createdAt: .distantPast,
                    updatedAt: .distantPast,
                    deletedAt: nil,
                    entryID: identifier(3),
                    order: index,
                    weight: Weight(grams: 32_500),
                    reps: reps,
                    rpe: nil,
                    rir: nil,
                    isWarmup: false,
                    isCompleted: true,
                    targetWeight: nil,
                    targetReps: nil,
                    modifiers: [],
                    notes: "",
                    completedAt: .distantPast)
            }

            /// The pinned commands, in the mode a checklist row draws them.
            static var commands: some View {
                SetEditorCommands(
                    showsRefusal: false,
                    mode: .row(SetEditorRow(plan: plan)),
                    log: {},
                    cancel: {},
                    skip: {},
                    delete: {})
            }

            /// The three fields `FR-17.1.6`'s budget is measured over.
            ///
            /// - Parameter draft: What the form holds.
            /// - Returns: The head.
            static func head(over draft: SetDraft) -> some View {
                SetEditorHead(
                    draft: .constant(draft),
                    mode: .row(SetEditorRow(plan: plan)),
                    equipment: Fixtures.equipment
                )
                .padding(Spacing.lg.points)
            }

            /// The whole sheet, composed.
            ///
            /// - Parameter draft: What the form holds.
            /// - Returns: The sheet, laid out for a reference.
            static func sheet(over draft: SetDraft) -> some View {
                VStack(spacing: Spacing.sm.points) {
                    SetEditorFields(
                        draft: .constant(draft),
                        mode: .row(SetEditorRow(plan: plan)),
                        vocabulary: Fixtures.vocabulary,
                        equipment: Fixtures.equipment
                    )
                    .padding(Spacing.lg.points)
                    commands
                }
            }

            /// A stable identifier, so a reference does not move because a UUID did.
            ///
            /// - Parameter seed: Which one.
            /// - Returns: The identifier.
            private static func identifier(_ seed: Int) -> UUID {
                UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", seed)) ?? UUID()
            }
        }
    }

#endif
