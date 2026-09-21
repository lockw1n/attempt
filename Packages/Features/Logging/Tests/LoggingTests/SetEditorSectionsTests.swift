import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-18.6.2`'s section builder — what the Log sheet opens holding over a checklist row.
///
/// **The six states are enumerable and all six are here**, keyed by (planned groups, logged
/// groups): (1, 0) is the commonest sheet in the app, (2, 0) is `F-10`'s own plan, (2, 1) is the
/// author's Day 2, (2, 2) is the reopen, (1, 2) is a row rewritten before this existed, and (0, 1)
/// is an exercise the lifter added.
@Suite("Log sheet sections")
struct SetEditorSectionsTests {
    static let locale = Locale(identifier: "en_US_POSIX")

    // MARK: - Building the sections

    @Test("A plan naming one group opens on one section, prefilled from it")
    func onePlannedNoneLogged() {
        let sections = Self.sections(plan: [Self.target(grams: 57_500, reps: 10, sets: 3)])

        #expect(sections.sections.count == 1)
        #expect(sections.single.weightText == "57.5")
        #expect(sections.single.repsText == "10")
        #expect(sections.single.setsText == "3")
        // The heading names a distinction this sheet does not have.
        #expect(sections.title(at: 0) == nil)
    }

    @Test("A plan naming two groups opens on two, in the plan's order")
    func twoPlannedNoneLogged() {
        let sections = Self.sections(plan: Self.twoGroupPlan)

        #expect(sections.sections.count == 2)
        #expect(sections.sections[0].draft.weightText == "57.5")
        #expect(sections.sections[0].draft.setsText == "3")
        #expect(sections.sections[1].draft.weightText == "100")
        #expect(sections.sections[1].draft.repsText == "8")
        #expect(sections.sections[1].draft.setsText == "2")
        #expect(sections.title(at: 0) != nil)
    }

    @Test("Planned two, logged one: the first section reads what was logged and the second the plan")
    func twoPlannedOneLogged() {
        let sections = Self.sections(
            plan: Self.twoGroupPlan, logged: Self.run(grams: 60_000, reps: [10, 10]))

        #expect(sections.sections.count == 2)
        // What was logged, not what was planned — 60 kg for two, against a plan of 57.5 for three.
        #expect(sections.sections[0].draft.weightText == "60")
        #expect(sections.sections[0].draft.setsText == "2")
        // And the plan, because nothing was logged here.
        #expect(sections.sections[1].draft.weightText == "100")
        #expect(sections.sections[1].draft.setsText == "2")
        // The pair is measured against this section's own group, never the whole plan.
        #expect(sections.sections[0].plan.map(\.reps) == [10])
        #expect(sections.sections[1].plan.map(\.reps) == [8])
    }

    @Test("Planned two, logged two: both sections read what is stored")
    func twoPlannedTwoLogged() {
        let sections = Self.sections(plan: Self.twoGroupPlan, logged: Self.twoGroupsLogged)

        #expect(sections.sections.count == 2)
        #expect(sections.sections[0].draft.repsText == "10")
        #expect(sections.sections[0].draft.setsText == "3")
        #expect(sections.sections[1].draft.repsText == "7")
        #expect(sections.sections[1].draft.setsText == "2")
    }

    @Test("More logged groups than the plan names: the extra ones get sections of their own, after")
    func onePlannedTwoLogged() {
        let sections = Self.sections(
            plan: [Self.target(grams: 57_500, reps: 10, sets: 3)], logged: Self.twoGroupsLogged)

        #expect(sections.sections.count == 2)
        #expect(sections.sections[0].draft.weightText == "57.5")
        #expect(sections.sections[1].draft.weightText == "100")
        // Nothing planned it, so there is nothing to measure it against.
        #expect(sections.sections[0].plan.count == 1)
        #expect(sections.sections[1].plan.isEmpty)
    }

    @Test("An exercise the lifter added, already logged: one section, prefilled from itself")
    func nothingPlannedOneLogged() {
        let sections = Self.sections(plan: [], logged: Self.run(grams: 20_000, reps: [12, 12]))

        #expect(sections.sections.count == 1)
        #expect(sections.single.weightText == "20")
        #expect(sections.single.setsText == "2")
        #expect(sections.sections[0].plan.isEmpty)
    }

    @Test("A row with neither a plan nor a set still opens on a form")
    func nothingPlannedNothingLogged() {
        let sections = Self.sections(plan: [], logged: [])

        #expect(sections.sections.count == 1)
        #expect(sections.single.weightText.isEmpty)
        #expect(sections.single.setsText == "1")
    }

    // MARK: - How the logged sets are partitioned

    @Test("Sections are matched to logged groups by position, never by load")
    func matchedByPosition() {
        // The plan's groups and the logged runs are in *opposite* order by load: matched on the
        // weight, section 1 would read 100 and section 2 would read 57.5, and the positional
        // rewrite that follows would write each group's numbers over the other's rows.
        let sections = Self.sections(
            plan: Self.twoGroupPlan,
            logged: Self.run(grams: 100_000, reps: [5]) + Self.run(grams: 57_500, reps: [12]))

        #expect(sections.sections[0].draft.weightText == "100")
        #expect(sections.sections[1].draft.weightText == "57.5")
    }

    @Test("Warm-ups before the first working set belong to the first section's fold")
    func warmupsLeadTheFirstSection() {
        let warmups = Self.run(grams: 20_000, reps: [10], from: 1, isWarmup: true)
        let logged = warmups + Self.twoGroupsLogged
        let groups = SetEditorSections.loggedGroups(logged)

        #expect(groups.count == 2)
        #expect(groups[0].count == 4)
        #expect(groups[0].first?.isWarmup == true)
        #expect(groups[1].allSatisfy { !$0.isWarmup })
        // Contiguous, in the stored order, and nothing dropped: what `rows` writes back has to
        // line up with the stored sets position for position.
        #expect(groups.flatMap { $0 }.map(\.id) == logged.map(\.id))
    }

    @Test("A warm-up between two runs joins the group that is open where it sits")
    func aWarmupBetweenRunsJoinsTheOpenGroup() {
        let logged =
            Self.run(grams: 57_500, reps: [10], from: 40)
            + Self.run(grams: 20_000, reps: [10], from: 50, isWarmup: true)
            + Self.run(grams: 100_000, reps: [7], from: 60)
        let groups = SetEditorSections.loggedGroups(logged)

        #expect(groups.count == 2)
        #expect(groups[0].count == 2)
        #expect(groups[1].count == 1)
        #expect(groups.flatMap { $0 }.map(\.id) == logged.map(\.id))
    }

    @Test("Nothing logged partitions into nothing")
    func nothingLoggedHasNoGroups() {
        #expect(SetEditorSections.loggedGroups([]).isEmpty)
    }

    // MARK: - What Save writes (FR-18.6.3, FR-18.6.4, Q-18.7)

    @Test("Every section's sets arrive as one list, in the plan's order")
    func rowsAreEverySectionInOrder() {
        let sections = Self.sections(plan: Self.twoGroupPlan)

        let rows = sections.rows

        #expect(rows.count == 5)
        #expect(rows.prefix(3).allSatisfy { $0.weight == Weight(grams: 57_500) && $0.reps == 10 })
        #expect(rows.suffix(2).allSatisfy { $0.weight == Weight(grams: 100_000) && $0.reps == 8 })
    }

    @Test("A section at zero sets writes nothing, and the rest still write")
    func aZeroSectionWritesNothing() {
        let sections = Self.zeroing(1, in: Self.sections(plan: Self.twoGroupPlan))

        #expect(sections.rows.count == 3)
        #expect(sections.rows.allSatisfy { $0.weight == Weight(grams: 57_500) })
        #expect(sections.isLoggable)
        #expect(!sections.writesNothing)
    }

    @Test("A section at zero sets whose load was never named still resolves")
    func aZeroSectionNeedsNoLoad() {
        // `FR-15.2.2`: a plan may name no load. A group the lifter did not do is not a group they
        // owe a weight for, so the exemption is what keeps that row saveable at all.
        var sections = Self.sections(
            plan: [
                Self.target(grams: 57_500, reps: 10, sets: 3),
                Self.target(grams: nil, reps: 8, sets: 2),
            ])
        #expect(sections.sections[1].draft.weightText.isEmpty)
        #expect(!sections.isLoggable)

        sections = Self.zeroing(1, in: sections)

        #expect(sections.isLoggable)
        #expect(sections.rows.count == 3)
    }

    @Test("Every section at zero disables Save rather than writing a skip")
    func everySectionAtZeroWritesNothing() {
        var sections = Self.zeroing(1, in: Self.sections(plan: Self.twoGroupPlan))

        sections = Self.zeroing(0, in: sections)

        #expect(sections.writesNothing)
        #expect(!sections.isLoggable)
        #expect(sections.rows.isEmpty)
    }

    @Test("A one-section sheet keeps the floor of one, so zero is a refusal rather than an answer")
    func oneSectionKeepsItsFloor() {
        var sections = Self.sections(plan: [Self.target(grams: 57_500, reps: 10, sets: 3)])

        sections = Self.zeroing(0, in: sections)

        // `sets` is nil rather than 0, which is what `writesNothing` asks about — so the sheet
        // refuses on submit instead of disabling the command.
        #expect(sections.single.sets == nil)
        #expect(!sections.writesNothing)
        #expect(!sections.isLoggable)
    }

    @Test("The ± pair floors a multi-section count at zero and a lone one at one")
    func theStepperFloorFollowsTheFloor() {
        let lone = Self.sections(plan: [Self.target(grams: 57_500, reps: 10, sets: 1)]).single
        let ofTwo = Self.sections(plan: Self.twoGroupPlan).sections[1].draft

        #expect(lone.adjustingSets(by: -1).setsText == "1")
        #expect(ofTwo.adjustingSets(by: -5).setsText == "0")
    }

    // MARK: - Fixtures

    static let entryID = UUID()

    static let twoGroupPlan: [WeekPlanTarget] = [
        target(grams: 57_500, reps: 10, sets: 3),
        target(grams: 100_000, reps: 8, sets: 2),
    ]

    static var twoGroupsLogged: [SetEntry] {
        run(grams: 57_500, reps: [10, 10, 10], from: 20)
            + run(grams: 100_000, reps: [7, 7], from: 30)
    }

    static func sections(plan: [WeekPlanTarget], logged: [SetEntry] = []) -> SetEditorSections {
        SetEditorSections(
            answering: SetEditorRow(plan: plan, logged: logged),
            unit: .kilograms,
            locale: Self.locale)
    }

    static func zeroing(_ index: Int, in sections: SetEditorSections) -> SetEditorSections {
        var zeroed = sections
        var draft = zeroed.sections[index].draft
        draft.setsText = "0"
        zeroed.replace(draft, at: index)
        return zeroed
    }

    static func target(grams: Int?, reps: Int, sets: Int) -> WeekPlanTarget {
        WeekPlanTarget(
            id: UUID(), weight: grams.map { Weight(grams: $0) }, reps: reps, sets: sets)
    }

    static func run(
        grams: Int, reps: [Int], from seed: Int = 0, isWarmup: Bool = false
    ) -> [SetEntry] {
        reps.enumerated().map { offset, count in
            SetEntry(
                id: UUID(),
                createdAt: .distantPast,
                updatedAt: .distantPast,
                deletedAt: nil,
                // One entry, because `SetGrouping` refuses to join sets from two — a fixture
                // minting one per set partitions into one group per set and says nothing.
                entryID: Self.entryID,
                order: seed + offset,
                weight: Weight(grams: grams),
                reps: count,
                rpe: nil,
                rir: nil,
                isWarmup: isWarmup,
                isCompleted: true,
                targetWeight: nil,
                targetReps: nil,
                modifiers: [],
                notes: "",
                completedAt: .distantPast)
        }
    }
}
