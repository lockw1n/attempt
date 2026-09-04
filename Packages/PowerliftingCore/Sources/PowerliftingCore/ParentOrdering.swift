/// Puts records that name a parent of their own kind into an order a store will accept.
public enum ParentOrdering {
    /// `items` reordered so that an item whose parent the collection also carries comes after it.
    ///
    /// **A self-referencing table is the one referential rule ordering by table cannot answer.** A
    /// repository refuses a foreign key naming a row that is not there yet, and an exercise
    /// variation names another exercise (`FR-1.1.7`) — so a writer walking the collection as given
    /// fails on the first child that happens to be listed above its parent, and whether it does is
    /// a property of the file rather than of the code.
    ///
    /// **Stable within that constraint**: an item the ordering does not have to move keeps its
    /// position, so a diff of what a writer wrote stays readable against its input.
    ///
    /// **Total on every input, malformed ones included.** An item naming a parent the collection
    /// does not carry is not held back — the row it needs may already be stored, and where it is
    /// not, the store is what names the fault. A parent chain that closes on itself cannot be
    /// ordered at all, so its members are emitted in their original order rather than looped over.
    ///
    /// - Parameters:
    ///   - items: The records, in whatever order they arrived.
    ///   - id: What identifies one.
    ///   - parentID: What it names as its parent, or `nil` where it names none.
    /// - Returns: The same records, parents first.
    public static func parentsFirst<Item, Key: Hashable>(
        _ items: [Item],
        id: (Item) -> Key,
        parentID: (Item) -> Key?
    ) -> [Item] {
        let present = Set(items.map(id))
        var emitted: Set<Key> = []
        var ordered: [Item] = []
        ordered.reserveCapacity(items.count)
        var pending = items

        while !pending.isEmpty {
            var deferred: [Item] = []
            for item in pending {
                // Blocked only by a parent this collection carries: one it does not is either
                // already stored or a fault the store will name, and holding the item back answers
                // neither.
                let waiting = parentID(item).map { present.contains($0) && !emitted.contains($0) }
                if waiting == true {
                    deferred.append(item)
                } else {
                    ordered.append(item)
                    emitted.insert(id(item))
                }
            }
            guard deferred.count < pending.count else {
                ordered.append(contentsOf: deferred)
                break
            }
            pending = deferred
        }
        return ordered
    }
}
