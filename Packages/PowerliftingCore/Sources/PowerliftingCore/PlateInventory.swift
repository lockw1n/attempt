/// The plates a gym owns, counted in **pairs** (`FR-1.4.2`).
///
/// Pairs rather than individual plates because a barbell is loaded symmetrically: an odd plate
/// cannot go on the bar, so counting singles would invite a loading that does not balance.
///
/// **No canonical set ships here.** Inventory is per equipment profile and the user has several
/// (`FR-1.4.3`), so the denominations are always supplied. A built-in competition set would be a
/// data claim this type has no need to make.
public struct PlateInventory: Sendable, Hashable {
    /// One denomination and how many pairs of it exist.
    public struct Entry: Sendable, Hashable {
        /// The mass of a single plate. At least one gram.
        public let plate: Weight

        /// How many pairs are available. Zero is legal — a profile may list a denomination the gym
        /// currently has none of.
        public let pairs: Int

        /// Creates one denomination. See ``PlateInventory/init(entries:)`` for what is rejected.
        public init(plate: Weight, pairs: Int) {
            self.plate = plate
            self.pairs = pairs
        }
    }

    /// The denominations, **heaviest first** whatever order they were supplied in.
    ///
    /// Ordering is normalised because it decides the order of a returned plate list, and a loading
    /// that depends on how a profile happened to be typed is not deterministic.
    public let entries: [Entry]

    /// The mass of every plate in the inventory, counted once per side.
    ///
    /// The most a single side can carry, so `bar + 2 × collar + 2 × totalPerSide` is the heaviest
    /// weight this inventory can produce.
    public let totalPerSide: Weight

    /// Creates an inventory, or returns `nil` if the denominations could not describe a gym.
    ///
    /// - Parameter entries: The denominations. May be empty — a bar with no plates is a real
    ///   profile and loads exactly one weight.
    /// - Returns: `nil` if any plate is under one gram, if any pair count is negative, if a
    ///   denomination is listed twice, or if the inventory's total mass overflows `Int`.
    ///
    ///   A repeated denomination is rejected rather than summed: two entries for 20 kg is far more
    ///   likely a duplicated row than a deliberate statement about two sets of 20s, and summing
    ///   would make the mistake invisible. The overflow rejection is what lets every later
    ///   calculation add plate masses without re-checking.
    public init?(entries: [Entry]) {
        var total = 0
        var seen: Set<Int> = []
        for entry in entries {
            guard entry.plate.grams >= 1, entry.pairs >= 0 else { return nil }
            guard seen.insert(entry.plate.grams).inserted else { return nil }
            let (mass, massOverflowed) = entry.plate.grams.multipliedReportingOverflow(by: entry.pairs)
            guard !massOverflowed else { return nil }
            let (running, sumOverflowed) = total.addingReportingOverflow(mass)
            guard !sumOverflowed else { return nil }
            total = running
        }
        self.entries = entries.sorted { $0.plate > $1.plate }
        self.totalPerSide = Weight(grams: total)
    }
}
