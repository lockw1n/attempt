import DerivedValues
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

    /// Whether the set was completed rather than failed (`FR-1.2.5`). It does **not** touch the
    /// numbering: a failed set was still performed, and skipping it would renumber the sets after
    /// it every time the user corrected one.
    var isCompleted: Bool { record.isCompleted }
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

/// A ``DerivedValues/SetGroup`` whose members carry their numbers (`FR-16.1.1`, `FR-1.2.14`).
///
/// **Numbers first, then the grouping over them.** A number is a position among sets of the same
/// kind, and grouping never mixes kinds, so a group's members are numbered consecutively and the
/// badge is the range `1–4` rather than a fifth number nothing else uses.
///
/// Never empty: ``SetNumbering/grouped(_:)`` builds these from runs that are non-empty by
/// construction.
struct NumberedSetGroup: Identifiable, Equatable {
    /// Its members, in order, each carrying its number.
    let members: [NumberedSet]

    /// The first of them — what every shared field is read off.
    var first: NumberedSet { members[0] }

    /// The group's id: its first set's, as ``DerivedValues/SetGroup/id``.
    var id: UUID { first.id }

    /// The set every shared field belongs to.
    var record: SetEntry { members[0].record }

    /// The last of them — the set `FR-16.1.4`'s **Log next set** copies.
    ///
    /// **Named rather than left to the caller**, because "the group's last member" is the write's
    /// own definition: the fields a group shares are read off ``first``, and the set the append
    /// copies is this one. They agree at ``DerivedValues/SetGrouping/Grain/displayed`` and the two
    /// questions are still different ones.
    var last: NumberedSet { members[members.count - 1] }

    /// How many sets it holds — the `× 4`.
    var count: Int { members.count }

    /// Whether it holds exactly one set, which is a row rather than a group.
    var isSingle: Bool { members.count == 1 }

    /// Whether these are warmups — which sequence the numbers belong to.
    var isWarmup: Bool { first.isWarmup }

    /// Whether they were completed rather than failed (`FR-1.2.5`).
    var isCompleted: Bool { first.isCompleted }

    /// The numbers it spans, first through last.
    var numbers: ClosedRange<Int> { first.number...last.number }

    /// The member rows drawn beneath the collapsed line, which is `FR-16.1.3` itself.
    ///
    /// **Every member or none, and the tap between the two is the only thing standing between the
    /// reader and a per-set control.** A group of one draws no members because it *is* its row —
    /// there is nothing folded away to open.
    ///
    /// - Parameter isExpanded: Whether the group is open.
    /// - Returns: The rows to draw under the line.
    func memberRows(isExpanded: Bool) -> [NumberedSet] {
        guard !isSingle, isExpanded else { return [] }
        return members
    }

    /// The planned group every member was logged against, or `nil` where they do not share one
    /// (`FR-15.3.1`).
    ///
    /// **The plan is not a compared field and it need not agree across a run.** Two planned groups
    /// can prescribe the same load and reps, so four identical sets can straddle them; drawn once,
    /// the collapsed line would name one member's target under all four. Where they differ the line
    /// belongs to the expanded rows, which are one tap away.
    ///
    /// - Parameter target: What was planned for one set, or `nil`.
    /// - Returns: The shared target, or `nil`.
    func sharedTarget(_ target: (UUID) -> PlannedTargetGroup?) -> PlannedTargetGroup? {
        let targets = members.map { target($0.id) }
        guard let first = targets.first, targets.allSatisfy({ $0?.id == first?.id }) else {
            return nil
        }
        return first
    }
}

extension SetNumbering {
    /// Groups numbered sets on `FR-16.1.1`'s rule, keeping each member's number.
    ///
    /// **The partition comes from ``DerivedValues/SetGrouping`` rather than from a second walk
    /// here.** The runs it returns concatenate back to what it was given, so the numbers are
    /// re-attached by position — which is what makes this a projection of the one rule rather than
    /// a copy of it.
    ///
    /// **At ``DerivedValues/SetGrouping/Grain/displayed``, which is `FR-16.1.2` rather than a
    /// default taken.** Every field a row draws breaks a run here — a rating, a note, a modifier,
    /// an outcome — because this is the partition a card draws its controls over, and the coarser
    /// grain would put one member's rating on a line standing for four.
    ///
    /// - Parameter sets: Numbered sets of one kind, in order.
    /// - Returns: The groups, in that order.
    static func grouped(_ sets: [NumberedSet]) -> [NumberedSetGroup] {
        var groups: [NumberedSetGroup] = []
        var start = sets.startIndex
        for group in SetGrouping.groups(sets.map(\.record), at: .displayed) {
            let end = start + group.count
            groups.append(NumberedSetGroup(members: Array(sets[start..<end])))
            start = end
        }
        return groups
    }
}
