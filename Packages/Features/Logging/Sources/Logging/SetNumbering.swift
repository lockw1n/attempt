import Foundation
import RepositoryInterface

/// One logged set and its place in its **own** sequence (`FR-1.2.14`).
///
/// **The number is a position among sets of the same kind, not in the exercise.** A warmup is `W1`
/// while the working set beside it is `1`, and that is the whole of the requirement: a lifter who
/// warms up three times and then works three times did three working sets, not sets four through
/// six. Reading either number as an index into ``SessionExercise/sets`` is therefore wrong.
struct NumberedSet: Identifiable, Equatable, Sendable {
    /// The set itself.
    ///
    /// **Named `record` rather than `set`**: a computed property whose body begins with `set` is
    /// parsed as a setter, so `{ set.id }` does not compile. The trap is worth the odd name.
    let record: SetEntry

    /// Its one-based place among the sets of its kind.
    let number: Int

    /// The set's id: one set is one row.
    var id: UUID { record.id }

    /// Whether this is a warmup — which sequence the number belongs to, and how the row is drawn.
    var isWarmup: Bool { record.isWarmup }
}

/// `FR-1.2.14`'s two independent sequences.
///
/// **A free function over the sets rather than a property of the card**, because the property the
/// requirement actually makes — that working-set numbering is never affected by warmups — is a
/// claim about a list, and a list is the smallest thing that can be handed to a test. Nothing here
/// reads a store, a view or a `SetEntry.order`.
///
/// **`order` is deliberately not the number.** It is zero-based, it counts both kinds together, and
/// it carries the gaps a soft-deleted set leaves (`G-1.3`) — so a card numbered from it would show
/// `1, 3, 4` after one deletion and would count a warmup as a working set besides.
enum SetNumbering {
    /// Numbers `sets`, warmups apart from working sets.
    ///
    /// **Two counters walked in one pass, and that is the requirement rather than an
    /// optimisation.** Each kind advances only its own counter, so inserting, removing or
    /// reclassifying a set of one kind cannot move a number of the other — which is what
    /// "working-set numbering is never affected by warmups" asks for, stated as code rather than as
    /// two filtered passes that would happen to agree.
    ///
    /// The order handed in is preserved, so a caller free to group the result by kind gets the same
    /// numbers as one that renders it flat: a number depends on how many sets of its own kind came
    /// before it, and partitioning a list does not change that for either kind.
    ///
    /// - Parameter sets: The exercise's sets, in the order they were logged.
    /// - Returns: The same sets, in the same order, each carrying its number.
    static func numbered(_ sets: [SetEntry]) -> [NumberedSet] {
        var warmups = 0
        var working = 0
        return sets.map { set in
            if set.isWarmup {
                warmups += 1
                return NumberedSet(record: set, number: warmups)
            }
            working += 1
            return NumberedSet(record: set, number: working)
        }
    }
}
