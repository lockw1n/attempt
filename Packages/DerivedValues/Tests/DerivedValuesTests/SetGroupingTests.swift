import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import DerivedValues

/// `FR-16.1.1`, `FR-16.1.2`, `NFR-16.2` and `DOD-16.5`: the grouping is a pure function over one
/// entry's sets, and every field a row draws breaks a run.
@Suite("Set grouping")
struct SetGroupingTests {
    @Test("No sets, no groups")
    func empty() {
        #expect(SetGrouping.groups([]).isEmpty)
    }

    @Test("One set is one group of one")
    func single() {
        let groups = SetGrouping.groups([set(order: 0)])
        #expect(groups.count == 1)
        #expect(groups[0].count == 1)
        #expect(groups[0].isSingle)
    }

    @Test("Four identical sets are one group of four")
    func run() {
        let sets = (0..<4).map { set(order: $0) }
        let groups = SetGrouping.groups(sets)
        #expect(groups.count == 1)
        #expect(groups[0].count == 4)
        #expect(!groups[0].isSingle)
        #expect(groups[0].weight == Weight(grams: 100_000))
        #expect(groups[0].reps == 6)
        #expect(groups[0].setIDs == sets.map(\.id))
    }

    @Test("A warmup between two equal working sets makes three groups")
    func warmupBreaksTheRun() {
        let groups = SetGrouping.groups([
            set(order: 0), set(order: 1, isWarmup: true), set(order: 2),
        ])
        #expect(groups.map(\.count) == [1, 1, 1])
        #expect(groups.map(\.isWarmup) == [false, true, false])
    }

    @Test("A failed set between two equal completed ones makes three groups")
    func outcomeBreaksTheRun() {
        let groups = SetGrouping.groups([
            set(order: 0), set(order: 1, isCompleted: false), set(order: 2),
        ])
        #expect(groups.map(\.count) == [1, 1, 1])
        #expect(groups.map(\.isCompleted) == [true, false, true])
    }

    @Test("A note on one set breaks the group")
    func noteBreaksTheRun() {
        let groups = SetGrouping.groups([
            set(order: 0), set(order: 1, notes: "belt on"), set(order: 2),
        ])
        #expect(groups.map(\.count) == [1, 1, 1])
    }

    @Test("A rating that changes breaks the group")
    func ratingBreaksTheRun() {
        let groups = SetGrouping.groups([set(order: 0, rpe: 8), set(order: 1, rpe: 9)])
        #expect(groups.map(\.count) == [1, 1])
    }

    @Test("A modifier that changes breaks the group")
    func modifierBreaksTheRun() {
        let groups = SetGrouping.groups([
            set(order: 0), set(order: 1, modifiers: [SetModifier(.belt)]),
        ])
        #expect(groups.map(\.count) == [1, 1])
    }

    @Test("Equal sets in a different order are not gathered together")
    func orderIsTheEntrysAndNeverSorted() {
        // A wave back up to the opening load: 100, 100, 90, 100 is three groups, and the fourth set
        // joins none of the first two. Sorting — or grouping by key rather than by run — would say
        // 100 × 6 × 3, which is a workout nobody performed.
        let groups = SetGrouping.groups([
            set(order: 0), set(order: 1), set(order: 2, grams: 90_000), set(order: 3),
        ])
        #expect(groups.map(\.count) == [2, 1, 1])
        #expect(
            groups.map(\.weight) == [
                Weight(grams: 100_000), Weight(grams: 90_000), Weight(grams: 100_000),
            ])
    }

    @Test("DOD-16.5: correcting the fourth set's reps re-reads as two groups")
    func aCorrectedSetRegroupsWithNoOtherWrite() {
        var sets = (0..<4).map { set(order: $0) }
        #expect(SetGrouping.groups(sets).map(\.count) == [4])
        // The one write the requirement allows: the set itself. Nothing else is touched, and the
        // grouping is read again from the same list.
        sets[3] = set(order: 3, reps: 5, id: sets[3].id)
        let regrouped = SetGrouping.groups(sets)
        #expect(regrouped.map(\.count) == [3, 1])
        #expect(regrouped.map(\.reps) == [6, 5])
    }

    @Test("Nothing is unreachable: the members concatenate back to what was handed in")
    func everySetSurvivesTheGrouping() {
        // The other half of `FR-16.1.3` — a set the grouping dropped could not be reached by any
        // number of taps. Over a list holding every shape at once.
        let sets = [
            set(order: 0, isWarmup: true), set(order: 1, isWarmup: true), set(order: 2),
            set(order: 3), set(order: 4, rpe: 9), set(order: 5, isCompleted: false),
            set(order: 6, notes: "last one"),
        ]
        #expect(SetGrouping.groups(sets).flatMap(\.setIDs) == sets.map(\.id))
    }

    @Test("The prescribing grain merges across what a routine cannot say")
    func loadAndRepsIgnoresTheFieldsAPlanHasNoRoomFor() {
        let sets = [
            set(order: 0, rpe: 8), set(order: 1, rpe: 9), set(order: 2, notes: "belt on"),
        ]
        #expect(SetGrouping.groups(sets, at: .displayed).map(\.count) == [1, 1, 1])
        #expect(SetGrouping.groups(sets, at: .loadAndReps).map(\.count) == [3])
    }

    @Test("The prescribing grain still breaks on load and on reps")
    func loadAndRepsIsNotAKeylessMerge() {
        let sets = [set(order: 0), set(order: 1, reps: 5), set(order: 2, grams: 90_000)]
        #expect(SetGrouping.groups(sets, at: .loadAndReps).map(\.count) == [1, 1, 1])
    }

    @Test("A group cannot be built over no sets")
    func anEmptyGroupIsRefused() {
        #expect(SetGroup([]) == nil)
        #expect(SetGroup([set(order: 0)]) != nil)
    }

    /// One set, with only what a test varies named.
    ///
    /// - Parameters:
    ///   - order: Its place among the entry's sets.
    ///   - grams: The load.
    ///   - reps: The repetitions.
    ///   - rpe: The rating, where it carried one.
    ///   - isWarmup: Whether it is a warmup.
    ///   - isCompleted: Whether it was completed rather than failed.
    ///   - notes: Its own note.
    ///   - modifiers: `FR-1.2.8`'s modifiers.
    ///   - id: Its identifier, where a test needs to hold on to one.
    /// - Returns: The set.
    private func set(
        order: Int,
        grams: Int = 100_000,
        reps: Int = 6,
        rpe: Double? = 8,
        isWarmup: Bool = false,
        isCompleted: Bool = true,
        notes: String = "",
        modifiers: [SetModifier] = [],
        id: UUID = UUID()
    ) -> SetEntry {
        SetEntry(
            id: id,
            createdAt: .distantPast,
            updatedAt: .distantPast,
            deletedAt: nil,
            entryID: entryID,
            order: order,
            weight: Weight(grams: grams),
            reps: reps,
            rpe: rpe,
            rir: nil,
            isWarmup: isWarmup,
            isCompleted: isCompleted,
            targetWeight: nil,
            targetReps: nil,
            modifiers: modifiers,
            notes: notes,
            completedAt: nil)
    }

    /// The entry every set here belongs to — grouping is a function over *one* entry's sets.
    private let entryID = UUID()
}
