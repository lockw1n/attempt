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

        // MARK: - The sections (FR-18.6.2, FR-18.6.4, FR-18.6.6)

        @Test func aPlanOfTwoGroupsOpensOnTwoSections() throws {
            // `F-10`, and the whole of what the task is for: the circle wrote both groups and the
            // sheet wrote one. What a picture settles here is that the second section is a form
            // rather than a line — three fields of its own, its own plan target, its own fold —
            // and that each section says which group it is.
            try assertSnapshots(named: "Log-sheet-two-sections") {
                fixedEnvironment {
                    LogSheetFixtures.sheet(
                        over: LogSheetFixtures.twoSections, plan: LogSheetFixtures.twoGroupPlan)
                }
            }
        }

        @Test func aDeviationInTheSecondGroupReopens() throws {
            // `FR-17.7.5` over `FR-18.6.2`: the row is answered, the second group was done one rep
            // short, and reopening prefills **both** sections from what is stored. Before this
            // task the same row reopened as one form reading `57.5 × 10 × 5`, which is neither
            // group.
            try assertSnapshots(named: "Log-sheet-two-sections-answered") {
                fixedEnvironment {
                    LogSheetFixtures.sheet(
                        over: LogSheetFixtures.twoSectionsAnswered,
                        plan: LogSheetFixtures.twoGroupPlan)
                }
            }
        }

        @Test func aSectionAtZeroSaysSoInWords() throws {
            // `FR-18.6.4` and `FR-18.6.5` in one picture: the back-offs were not done, the count
            // reads 0, and the Actual line says **Not done** rather than rendering `× 0` — which
            // is `G-4.5`, a number nobody entered being indistinguishable from one they did.
            try assertSnapshots(named: "Log-sheet-section-not-done") {
                fixedEnvironment {
                    LogSheetFixtures.sheet(
                        over: LogSheetFixtures.secondSectionNotDone,
                        plan: LogSheetFixtures.twoGroupPlan)
                }
            }
        }

        @Test func everySectionAtZeroDisablesSave() throws {
            // `Q-18.7`'s answer, which is a *disabled* command and a line naming the one below it.
            // The claim a picture carries that no test does is that the two read as different
            // things: the refusal is negative and this is guidance.
            try assertSnapshots(named: "Log-sheet-every-section-empty") {
                fixedEnvironment {
                    LogSheetFixtures.sheet(
                        over: LogSheetFixtures.everySectionEmpty,
                        plan: LogSheetFixtures.twoGroupPlan)
                }
            }
        }

        @Test func theSecondSectionHasAFoldOfItsOwn() throws {
            // `FR-18.6.6`. The fold is opened on the **second** section deliberately: it holds
            // that group's rows and no other's, which is the half a one-section sheet could not
            // have had at all — and it keeps the render inside the height a reference can hold,
            // where two open folds at `accessibility3` would not.
            try assertSnapshots(named: "Log-sheet-second-fold") {
                fixedEnvironment {
                    LogSheetFixtures.sheet(
                        over: LogSheetFixtures.secondSectionFoldOpen,
                        plan: LogSheetFixtures.twoGroupPlan)
                }
            }
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
            static var unanswered: SetEditorSections { sections(plan: plan) }

            /// The same form with the reps brought down to eight — DOD-17.7's answer.
            static var deviating: SetEditorSections {
                edited(unanswered, at: 0) { $0.repsText = "8" }
            }

            /// The fold open over three sets.
            static var perSet: SetEditorSections {
                edited(deviating, at: 0) {
                    $0 = $0.openingDetails()
                    $0.details[2].repsText = "6"
                }
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
            static var answered: SetEditorSections { sections(plan: plan, logged: logged) }

            /// Two stored sets that agree with each other, at a load the plan did not name.
            static let logged: [SetEntry] = run(grams: 32_500, reps: [8, 8], from: 10)

            // MARK: - FR-18.6's sections

            /// A plan naming two groups — a top set and back-offs, the shape `F-10` was reported
            /// over.
            ///
            /// **The two lines differ in rendered width rather than only in their numbers.** A
            /// fixture whose groups render the same length can picture every *state* a section
            /// has and still not picture a row changing shape under one, which is what `T-18.07`
            /// found about the plan scheme's own layout.
            static let twoGroupPlan: [WeekPlanTarget] = [
                WeekPlanTarget(id: identifier(1), weight: Weight(grams: 57_500), reps: 10, sets: 3),
                WeekPlanTarget(id: identifier(2), weight: Weight(grams: 100_000), reps: 8, sets: 2),
            ]

            /// `FR-18.6.2`'s own state: two planned groups, nothing logged against either.
            static var twoSections: SetEditorSections { sections(plan: twoGroupPlan) }

            /// A two-group row already answered with the **second** group one rep short — the
            /// state `F-10` made unreachable, and `DOD-18.3`'s rewrite.
            static var twoSectionsAnswered: SetEditorSections {
                sections(plan: twoGroupPlan, logged: twoGroupsLogged)
            }

            /// `FR-18.6.4`: the back-offs were not done, so that section is at zero and its pair
            /// says so in words rather than as `× 0`.
            static var secondSectionNotDone: SetEditorSections {
                edited(twoSections, at: 1) { $0.setsText = "0" }
            }

            /// `FR-18.6.6`, over the **second** section — the fold a one-section sheet could never
            /// have shown, holding that group's rows and no other's.
            static var secondSectionFoldOpen: SetEditorSections {
                edited(twoSections, at: 1) {
                    $0 = $0.openingDetails()
                    $0.details[1].repsText = "6"
                }
            }

            /// Every section at zero — the one state **Save as done** is disabled in (`Q-18.7`).
            static var everySectionEmpty: SetEditorSections {
                edited(secondSectionNotDone, at: 0) { $0.setsText = "0" }
            }

            /// Two logged runs — `57.5 × 10 × 3`, then `100 × 7 × 2` against a target of eight.
            static var twoGroupsLogged: [SetEntry] {
                run(grams: 57_500, reps: [10, 10, 10], from: 20)
                    + run(grams: 100_000, reps: [7, 7], from: 30)
            }

            /// What the sheet opens holding over a row.
            ///
            /// - Parameters:
            ///   - plan: What the routine prescribed.
            ///   - logged: What is already stored against it.
            /// - Returns: One section per group.
            static func sections(
                plan: [WeekPlanTarget], logged: [SetEntry] = []
            ) -> SetEditorSections {
                SetEditorSections(
                    answering: SetEditorRow(plan: plan, logged: logged),
                    unit: .kilograms,
                    locale: Self.numberLocale)
            }

            /// One section's draft, changed.
            ///
            /// - Parameters:
            ///   - sections: What the sheet held.
            ///   - index: Which section moves.
            ///   - change: What the lifter did to it.
            /// - Returns: The sheet, with that one section changed.
            static func edited(
                _ sections: SetEditorSections, at index: Int, _ change: (inout SetDraft) -> Void
            ) -> SetEditorSections {
                var edited = sections
                var draft = edited.sections[index].draft
                change(&draft)
                edited.replace(draft, at: index)
                return edited
            }

            /// A run of completed sets at one load.
            ///
            /// - Parameters:
            ///   - grams: The load.
            ///   - reps: One count per set.
            ///   - seed: Where the stable identifiers and the stored order start.
            /// - Returns: The sets, in order.
            static func run(grams: Int, reps: [Int], from seed: Int) -> [SetEntry] {
                reps.enumerated().map { offset, count in
                    SetEntry(
                        id: identifier(seed + offset),
                        createdAt: .distantPast,
                        updatedAt: .distantPast,
                        deletedAt: nil,
                        entryID: identifier(3),
                        order: seed + offset,
                        weight: Weight(grams: grams),
                        reps: count,
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
            }

            // MARK: - The views

            /// The pinned commands, in the mode a checklist row draws them.
            static var commands: some View { commands(canSave: true) }

            /// The pinned commands, with the confirming one in the state the sections put it in.
            ///
            /// - Parameter canSave: Whether anything would be written (`Q-18.7`).
            /// - Returns: The commands.
            static func commands(canSave: Bool) -> some View {
                SetEditorCommands(
                    showsRefusal: false,
                    canSave: canSave,
                    mode: .row(SetEditorRow(plan: plan)),
                    log: {},
                    cancel: {},
                    skip: {},
                    delete: {})
            }

            /// The three fields `FR-17.1.6`'s budget is measured over.
            ///
            /// **`sectionTitle` is passed rather than left to default.** It and `isFirstSection`
            /// default to the one-section values, so a fixture naming neither draws a head with no
            /// group heading however many sections it was handed — which is how this one's first
            /// version made a two-section head measure the same as a one-section head, and the
            /// test over it an equality that could not fail (`T-18.08`, `T-17.01` inverted).
            ///
            /// - Parameter sections: What the form holds — the first section's fields are the ones
            ///   measured (`FR-18.6.1`), with the heading that section actually draws.
            /// - Returns: The head.
            static func head(over sections: SetEditorSections) -> some View {
                SetEditorHead(
                    draft: .constant(sections.single),
                    mode: .row(SetEditorRow(plan: plan)),
                    equipment: Fixtures.equipment,
                    sectionTitle: sections.title(at: 0),
                    isFirstSection: true
                )
                .padding(Spacing.lg.points)
            }

            /// The whole sheet, composed.
            ///
            /// **``SetEditorRowFields`` rather than its parts**, which is `T-17.01`'s rule: a
            /// fixture that assembles a screen's components can picture one the screen omits, and
            /// every gate in this repository was clean when four of these references did.
            ///
            /// - Parameters:
            ///   - sections: What the form holds.
            ///   - plan: The row's plan, which is what decides how many sections there are.
            /// - Returns: The sheet, laid out for a reference.
            static func sheet(
                over sections: SetEditorSections, plan: [WeekPlanTarget] = plan
            ) -> some View {
                VStack(spacing: Spacing.sm.points) {
                    form(over: sections, plan: plan, skip: {})
                        .padding(Spacing.lg.points)
                    commands(canSave: !sections.writesNothing)
                }
            }

            /// The sheet's scrolling half — every section, and the skip where the sheet's room has
            /// put it there (`FR-18.6.9`).
            ///
            /// **`skip:` is passed at every call rather than defaulted, and the view has no default
            /// either.** At an accessibility size this is a whole command that moved into this
            /// region; a fixture that could leave it out would picture the sheet with **Skip this
            /// exercise** nowhere at all, which is the shape a re-record exists to catch.
            ///
            /// - Parameters:
            ///   - sections: What the form holds.
            ///   - plan: The row's plan, which decides how many sections there are.
            ///   - skip: The command, or `nil` for a sheet that offers none.
            /// - Returns: The scrolling form.
            static func form(
                over sections: SetEditorSections,
                plan: [WeekPlanTarget] = plan,
                skip: (() -> Void)?
            ) -> some View {
                SetEditorRowFields(
                    sections: .constant(sections),
                    mode: .row(SetEditorRow(plan: plan)),
                    vocabulary: Fixtures.vocabulary,
                    equipment: Fixtures.equipment,
                    skip: skip)
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
