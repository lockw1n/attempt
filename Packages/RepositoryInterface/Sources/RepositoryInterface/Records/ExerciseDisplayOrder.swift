import Foundation

/// The order a browsable surface shows exercises in (`FR-1.14.2`, `FR-18.1.2`).
///
/// **One home for the rule, in the module that owns the name it sorts on.** A list whose rows read
/// Cyrillic and whose order was fixed by their English names has no order its reader can use, and
/// the two are not the same permutation — `localizedStandardCompare` sorts scripts apart. Every
/// surface that draws exercise names sorts through here, in this module and in the feature modules
/// above it, so no two of them can disagree.
public enum ExerciseDisplayOrder {
    /// `exercises` with each parent followed by its variations, by the names shown in `language`.
    ///
    /// Roots run in name order, and each is followed at once by every row below it in name order —
    /// one flat run, so a variation of a variation sits in its root's run rather than under its own
    /// parent. **A root is a row whose parent is not in `exercises`, or that lies on a cycle**, and a
    /// custom `A → B → A` terminates with both as roots. So the answer depends on which rows are
    /// handed in: **order the rows a screen draws, after its search, filters and sections**, or a
    /// variation whose parent they left out keeps its place under a parent nobody sees. A caller
    /// handing in only roots (a parent picker) or only one parent's children (a detail screen's
    /// variations) gets plain name order, which is this rule's answer for those inputs.
    ///
    /// The identifier breaks a tie at both levels because `G-2.5` forbids a unique constraint on the
    /// name and `Array.sorted` is not stable — two exercises reading alike would otherwise swap
    /// places between two reads of one catalogue.
    ///
    /// - Parameters:
    ///   - exercises: The rows to order.
    ///   - language: Which of the two names the caller is showing. No default: a caller that has
    ///     not decided which name it shows has not decided what its order means either.
    /// - Returns: The same exercises, ordered; none dropped, none repeated.
    public static func sorted(
        _ exercises: [Exercise], in language: ExerciseNameLanguage
    ) -> [Exercise] {
        sorted(
            exercises,
            id: \.id,
            parentID: \.parentExerciseID,
            name: { $0.displayName(in: language) })
    }

    /// `rows` in ``sorted(_:in:)``'s order, for a surface whose rows are not ``Exercise`` values —
    /// a picker that has already resolved each name.
    ///
    /// Each name is read once rather than once per comparison: a screen recomputes its order on
    /// every render, which is the only way this is ever hot.
    ///
    /// - Parameters:
    ///   - rows: The rows to order.
    ///   - id: The exercise a row is.
    ///   - parentID: The exercise it is a variation of, or `nil` for none.
    ///   - name: The name the row shows.
    /// - Returns: The same rows, ordered; none dropped, none repeated.
    public static func sorted<Row>(
        _ rows: [Row], id: (Row) -> UUID, parentID: (Row) -> UUID?, name: (Row) -> String
    ) -> [Row] {
        let entries = rows.map { Entry(id: id($0), parentID: parentID($0), name: name($0), row: $0) }
        let family = Family(
            present: Set(entries.map(\.id)),
            parentOf: Dictionary(
                entries.compactMap { entry in entry.parentID.map { (entry.id, $0) } },
                uniquingKeysWith: { first, _ in first }))
        let roots = Set(entries.map(\.id).filter { isRoot($0, in: family) })
        var runs: [UUID: [Entry<Row>]] = [:]
        for entry in entries where !roots.contains(entry.id) {
            runs[root(of: entry.id, among: roots, in: family), default: []].append(entry)
        }
        let orderedRoots = byName(entries.filter { roots.contains($0.id) })
        // A row stored twice under one identifier is two roots with one run, and the run follows
        // the last of them — once, so the output holds exactly what the input did.
        let lastIndex = Dictionary(
            orderedRoots.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { _, last in last })
        return orderedRoots.enumerated().flatMap { index, root in
            lastIndex[root.id] == index ? [root] + byName(runs[root.id] ?? []) : [root]
        }
        .map(\.row)
    }

    /// A row with its identifier, parent and name read once.
    private struct Entry<Row> {
        /// The exercise the row is.
        let id: UUID

        /// The exercise it is a variation of.
        let parentID: UUID?

        /// The name it shows.
        let name: String

        /// The row itself.
        let row: Row
    }

    /// Which exercises are in the input, and the parent each one names.
    private struct Family {
        /// Every identifier in the input.
        let present: Set<UUID>

        /// Each row's parent, for the rows that name one — present in the input or not.
        let parentOf: [UUID: UUID]

        /// `id`'s parent where the input holds it, or `nil` where it names none or an absent one.
        func parent(of id: UUID) -> UUID? {
            parentOf[id].flatMap { present.contains($0) ? $0 : nil }
        }
    }

    /// Whether `id` starts a run: its parent is not in the input, or following parents leads back
    /// to it.
    private static func isRoot(_ id: UUID, in family: Family) -> Bool {
        var seen: Set<UUID> = [id]
        var current = id
        while let parent = family.parent(of: current) {
            if parent == id { return true }
            // A cycle above this row but not through it: this row is not on it, and the walk from
            // it reaches a cycle member, which is a root.
            guard seen.insert(parent).inserted else { return false }
            current = parent
        }
        return current == id
    }

    /// The first root at or above `id`. Terminates: every walk upward ends at a row whose parent is
    /// absent or enters a cycle, and both are roots.
    private static func root(of id: UUID, among roots: Set<UUID>, in family: Family) -> UUID {
        var current = id
        while !roots.contains(current), let parent = family.parent(of: current) {
            current = parent
        }
        return current
    }

    /// Plain name order, the identifier breaking a tie.
    private static func byName<Row>(_ entries: [Entry<Row>]) -> [Entry<Row>] {
        entries.sorted { lhs, rhs in
            let byName = lhs.name.localizedStandardCompare(rhs.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
