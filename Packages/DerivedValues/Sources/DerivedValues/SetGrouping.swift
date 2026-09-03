import Foundation
import PowerliftingCore
import RepositoryInterface

/// A run of consecutive sets that read as one line — `100 kg × 6 × 4` (`FR-16.1.1`).
///
/// **Never stored, and never empty** (`NFR-16.2`). It is recomputed on every read, so an edit to one
/// set re-groups with no second write (`FR-16.1.2`); and a group with no sets in it would have no
/// load, no reps and no identity, which is why the only public way to build one refuses that.
///
/// **A group of one is a set, not a group.** The distinction belongs to the caller — see
/// ``isSingle`` — because a surface that draws controls per set draws them differently for the two,
/// and one that only reads does not care.
public struct SetGroup: Identifiable, Equatable, Sendable {
    /// Its members, in the order they were logged. Never empty.
    public let sets: [SetEntry]

    /// The first of them, which every shared field is read off.
    public var first: SetEntry { sets[0] }

    /// The group's id: its first set's, so a group keeps its identity while sets are appended to it.
    public var id: UUID { first.id }

    /// The load every member carried (`TR-0.2.3`).
    public var weight: Weight { first.weight }

    /// The repetitions every member carried.
    public var reps: Int { first.reps }

    /// How many sets it holds — the `× 4`.
    public var count: Int { sets.count }

    /// Its members' ids, in order.
    public var setIDs: [UUID] { sets.map(\.id) }

    /// Whether these are warmups (`G-1.8`).
    public var isWarmup: Bool { first.isWarmup }

    /// Whether they were completed rather than failed (`FR-1.2.5`).
    public var isCompleted: Bool { first.isCompleted }

    /// The rating every member carried, or none.
    public var rpe: Double? { first.rpe }

    /// Whether it holds exactly one set.
    public var isSingle: Bool { sets.count == 1 }

    /// Builds a group over sets a caller has already run together.
    ///
    /// - Parameter sets: Its members, in order.
    /// - Returns: The group, or `nil` where there are no sets to make one of.
    public init?(_ sets: [SetEntry]) {
        guard !sets.isEmpty else { return nil }
        self.sets = sets
    }

    /// The unchecked form the grouping below builds, whose runs are non-empty by construction.
    ///
    /// - Parameter run: A non-empty run of sets.
    fileprivate init(run: [SetEntry]) {
        sets = run
    }
}

/// `FR-16.1.1`'s grouping: one pure function over one entry's sets (`NFR-16.2`).
///
/// **One rule asked at two grains rather than two rules.** `FR-16.1.2` breaks a display group on any
/// difference, while `FR-15.2.6`'s routine is written in loads and reps alone — a rating that
/// drifted across four back-off sets is four lines to read and one line to prescribe. Expressing
/// that as a second walk is how the two start disagreeing about what a run is.
///
/// **The order handed in is the order out.** Sets are grouped where they are *consecutive*, never
/// where they are merely equal: a wave back up to the opening load is a third group and not a bigger
/// first one, and sorting would erase the difference.
public enum SetGrouping {
    /// How closely two sets have to match to share a group.
    public enum Grain: Sendable {
        /// Every field a set row draws — what `FR-16.1.2` breaks a group on.
        ///
        /// **Modifiers are compared, though `FR-16.1.2`'s list stops at the note.** The requirement's
        /// rule is that any difference breaks a group, and the list is what it names rather than
        /// what a row draws; a group whose members carried different modifiers would draw one
        /// member's under all of them, which is the collapsed line asserting something false about
        /// the sets behind it.
        case displayed

        /// The load and the repetitions alone.
        ///
        /// **For a reader that draws nothing else**, of which there are two: `FR-15.2.6`'s routine,
        /// which has nowhere to put a rating or a note, and `FR-1.2.10`'s strip, which has already
        /// dropped the warmups and the failures before it groups. Both would otherwise split a run
        /// on a field they do not show, which is a break with nothing visible behind it.
        case loadAndReps
    }

    /// Groups one entry's sets.
    ///
    /// - Parameters:
    ///   - sets: The sets logged against one entry, in order.
    ///   - grain: How closely two of them have to match to run together.
    /// - Returns: The groups, in that order. Concatenating their members gives `sets` back.
    public static func groups(_ sets: [SetEntry], at grain: Grain = .displayed) -> [SetGroup] {
        var runs: [[SetEntry]] = []
        for set in sets {
            if let previous = runs.last?.last, grain.joins(previous, set) {
                runs[runs.count - 1].append(set)
            } else {
                runs.append([set])
            }
        }
        return runs.map { SetGroup(run: $0) }
    }
}

extension SetGrouping.Grain {
    /// Whether `next` continues the run `previous` is in.
    ///
    /// - Parameters:
    ///   - previous: The last set of the run so far.
    ///   - next: The set being placed.
    /// - Returns: Whether the two share a group.
    fileprivate func joins(_ previous: SetEntry, _ next: SetEntry) -> Bool {
        guard previous.weight == next.weight, previous.reps == next.reps else { return false }
        switch self {
        case .loadAndReps:
            return true
        case .displayed:
            return previous.isWarmup == next.isWarmup
                && previous.isCompleted == next.isCompleted
                && previous.rpe == next.rpe
                && previous.notes == next.notes
                && previous.modifiers == next.modifiers
        }
    }
}
