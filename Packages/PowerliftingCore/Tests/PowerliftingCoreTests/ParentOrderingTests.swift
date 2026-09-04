import Testing

@testable import PowerliftingCore

/// The ordering a self-referencing table needs before a store will accept it.
///
/// **The subject is a table's own referential rule, not the exercise catalogue's.** Two callers
/// write `parentExerciseID` from a collection they did not order — the seed importer from an
/// authored payload, the restore from a backup file — and both fail on the first child listed above
/// its parent. The fixture here is a pair of `(id, parent)` rows so the rule is tested where it
/// lives rather than through either of them.
@Suite("Parent ordering")
struct ParentOrderingTests {
    /// One row of a self-referencing table.
    private struct Row: Equatable {
        /// What identifies it.
        let id: Int

        /// What it names as its parent, or `nil`.
        let parent: Int?
    }

    /// The ordering under test, over ``Row``.
    ///
    /// - Parameter rows: The rows as they arrived.
    /// - Returns: Their identifiers, parents first.
    private func ordered(_ rows: [Row]) -> [Int] {
        ParentOrdering.parentsFirst(rows, id: \.id, parentID: \.parent).map(\.id)
    }

    @Test("A child listed above its parent is moved below it")
    func aChildMovesBelowItsParent() {
        #expect(ordered([Row(id: 2, parent: 1), Row(id: 1, parent: nil)]) == [1, 2])
    }

    @Test("A chain is ordered however deep it is, and from any starting order")
    func aChainIsOrdered() {
        // Reversed, so every one of the three is blocked on its first pass: a single deferral round
        // would emit [1, 3, 2] and pass a test that only checked the parent came first.
        let rows = [Row(id: 3, parent: 2), Row(id: 2, parent: 1), Row(id: 1, parent: nil)]
        #expect(ordered(rows) == [1, 2, 3])
    }

    @Test("Rows the ordering need not move keep their positions")
    func theOrderingIsStable() {
        // Anchored on the whole sequence rather than on the pair that moved: an implementation that
        // sorted roots first would also put 2 after 1, and would reorder 10 and 20 for no reason.
        let rows = [
            Row(id: 10, parent: nil), Row(id: 2, parent: 1), Row(id: 20, parent: nil),
            Row(id: 1, parent: nil),
        ]
        #expect(ordered(rows) == [10, 20, 1, 2])
    }

    @Test("A parent the collection does not carry is not held back")
    func anAbsentParentIsNotHeldBack() {
        // The row may name something already stored, and where it does not, the store is what says
        // so — holding it back answers neither and would drop it from the output entirely.
        #expect(ordered([Row(id: 2, parent: 99), Row(id: 1, parent: nil)]) == [2, 1])
    }

    @Test("A cycle is emitted rather than looped over")
    func aCycleTerminates() {
        // Total on every input: two rows naming each other cannot be ordered at all, so they come
        // out in the order they went in and the store refuses them.
        #expect(ordered([Row(id: 1, parent: 2), Row(id: 2, parent: 1)]) == [1, 2])
    }

    @Test("A cycle does not take the rows around it with it")
    func aCycleDoesNotStrandTheRestOfTheTable() {
        // The guard breaks the whole loop, so the orderable rows have to be emitted before it is
        // reached rather than appended behind the cycle.
        let rows = [
            Row(id: 1, parent: 2),
            Row(id: 2, parent: 1),
            Row(id: 4, parent: 3),
            Row(id: 3, parent: nil),
        ]
        #expect(ordered(rows) == [3, 4, 1, 2])
    }

    @Test("An empty collection orders to an empty one")
    func nothingOrdersToNothing() {
        #expect(ordered([]).isEmpty)
    }
}
