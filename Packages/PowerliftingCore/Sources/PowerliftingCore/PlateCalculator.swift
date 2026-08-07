/// What to put on the bar for a target weight, and what to do when the target will not load
/// (`TR-0.2.7`, `FR-1.4.4`).
///
/// **``collar`` is the mass of one collar; two are always fitted.** A loaded bar is therefore
/// `bar + 2 × collar + 2 × (per-side plates)`. Collars are counted even when no plates are on the
/// bar, because they belong to the equipment profile rather than to the loading.
///
/// **Bar and collar are inputs, never derived from an exercise.** `BarType` is a category and
/// carries no mass: a men's 20 kg bar and a women's 15 kg bar are both `.standard`. Mass comes from
/// the equipment profile, which is per gym and of which a user has several (`FR-1.4.2`,
/// `FR-1.4.3`).
///
/// **The nearest achievable weights are exact for any inventory, not just canonical ones.** Taking
/// the heaviest plate that fits and moving on is wrong for a sparse gym — with one pair of 20 kg
/// and two pairs of 15 kg, it reports a 80 kg target as unloadable while 15 + 15 a side loads it
/// exactly. Every achievable per-side sum is enumerated instead, so "nearest above" and "nearest
/// below" mean what they say.
///
/// **No ``RoundingRule`` is involved, deliberately.** The inventory already says what is loadable,
/// exactly; an increment would be a second, coarser model of the same fact, and applying it first
/// would discard a target that the gym's smaller pairs load precisely. Rounding a percentage to a
/// sensible target belongs upstream, before a weight reaches this type.
public struct PlateCalculator: Sendable {
    /// The bar's own mass. Never negative.
    public let bar: Weight

    /// The mass of **one** collar. Never negative; two are fitted.
    public let collar: Weight

    /// The plates available, per side, in pairs.
    public let inventory: PlateInventory

    /// The bar and both collars — the lightest weight this calculator can produce.
    private let baseGrams: Int

    /// The largest denomination stocked, or zero for an inventory with no plates in it.
    private let heaviestPlateGrams: Int

    /// Creates a calculator for one equipment profile.
    ///
    /// - Parameters:
    ///   - bar: The bar's mass. Must not be negative.
    ///   - collar: The mass of one collar. Must not be negative; pass ``Weight/zero`` for a bar
    ///     loaded without them.
    ///   - inventory: The plates available.
    /// - Returns: `nil` for a negative bar or collar, or if the heaviest weight the profile could
    ///   load overflows `Int`. That second check is what lets every later addition of plate masses
    ///   proceed without re-testing for overflow.
    public init?(bar: Weight, collar: Weight, inventory: PlateInventory) {
        guard bar.grams >= 0, collar.grams >= 0,
            let collars = Self.doubled(collar.grams),
            let base = Self.sum(bar.grams, collars),
            let bothSides = Self.doubled(inventory.totalPerSide.grams),
            Self.sum(base, bothSides) != nil
        else {
            return nil
        }
        self.bar = bar
        self.collar = collar
        self.inventory = inventory
        self.baseGrams = base
        self.heaviestPlateGrams = inventory.entries.first?.plate.grams ?? 0
    }

    /// The loading for `target`, or the closest loadings either side of it.
    ///
    /// - Parameter target: The weight wanted on the bar. May be lighter than the bar itself, or
    ///   negative, in which case nothing sits below it and the bar alone sits above.
    /// - Returns: ``PlateLoadingResult/exact(_:)`` when the target loads, otherwise
    ///   ``PlateLoadingResult/nearest(below:above:)``.
    ///
    ///   Where several loadings reach the same weight, the one with the fewest plates wins; where
    ///   several tie on that too, the one using more of the heavier plate does. So a 20 is preferred
    ///   to two 10s, and the answer does not depend on the order the inventory was written in.
    public func loading(for target: Weight) -> PlateLoadingResult {
        let (budget, overflowed) = target.grams.subtractingReportingOverflow(baseGrams)
        guard !overflowed, budget >= 0 else {
            return .nearest(below: nil, above: barOnly)
        }

        // A loading is base + 2 × (per-side sum), so `budget` splits evenly across the two sides and
        // an odd gram is simply not loadable. The halving is written out rather than hidden in a
        // division operator: `budget` is non-negative here, so `/ 2` is the floor, and the remainder
        // is what separates the floor from the ceiling.
        let floorBudget = budget / 2
        let ceilBudget = floorBudget + budget % 2

        let reached = reachableLoadings(upTo: cap(forPerSideBudget: ceilBudget))
        if budget % 2 == 0, let counts = reached[floorBudget] {
            return .exact(loading(perSide: counts))
        }

        let below = reached.keys.filter { $0 <= floorBudget }.max()
        let above = reached.keys.filter { $0 >= ceilBudget }.min()
        return .nearest(
            below: below.flatMap { reached[$0] }.map { loading(perSide: $0) },
            above: above.flatMap { reached[$0] }.map { loading(perSide: $0) }
        )
    }
}

// MARK: - Enumeration

extension PlateCalculator {
    /// The bar and its collars, carrying nothing.
    private var barOnly: PlateLoading {
        loading(perSide: Array(repeating: 0, count: inventory.entries.count))
    }

    /// Every per-side plate sum up to `cap`, each mapped to the best way of reaching it.
    ///
    /// The value is a count per denomination, positionally matching ``PlateInventory/entries``.
    /// "Best" is the fewest plates, then more of the heavier denomination — a total order, so the
    /// result does not depend on the order this walks its own storage in.
    private func reachableLoadings(upTo cap: Int) -> [Int: [Int]] {
        var reached: [Int: [Int]] = [0: Array(repeating: 0, count: inventory.entries.count)]
        for (index, entry) in inventory.entries.enumerated() where entry.pairs > 0 {
            var extended = reached
            for (sum, counts) in reached {
                for used in 1...entry.pairs {
                    // Cannot overflow: the initialiser proved twice the whole inventory fits in
                    // `Int`, and `sum` plus this denomination's share is bounded by that.
                    let candidateSum = sum + entry.plate.grams * used
                    if candidateSum > cap { break }
                    var candidate = counts
                    candidate[index] = used
                    if let rival = extended[candidateSum], !Self.isPreferred(candidate, over: rival) {
                        continue
                    }
                    extended[candidateSum] = candidate
                }
            }
            reached = extended
        }
        return reached
    }

    /// How far above `budget` enumeration has to go to be sure of finding the nearest sum above it.
    ///
    /// One heaviest plate is enough. If `S` is the smallest achievable sum at or above `budget` and
    /// `S` is not `budget` itself, then `S` contains some plate `p`, and `S - p` is achievable and
    /// smaller, so `S - p` must fall below `budget` — which puts `S` under `budget + p`.
    private func cap(forPerSideBudget budget: Int) -> Int {
        let total = inventory.totalPerSide.grams
        guard budget < total else { return total }
        // Cannot overflow: `budget < total`, the heaviest plate is itself no more than `total`, and
        // the initialiser proved that twice `total` fits in `Int`.
        return min(total, budget + heaviestPlateGrams)
    }

    /// A loading from a count per denomination, dropping the denominations it does not use.
    private func loading(perSide counts: [Int]) -> PlateLoading {
        var plates: [PlateCount] = []
        var perSideGrams = 0
        for (index, entry) in inventory.entries.enumerated() where counts[index] > 0 {
            plates.append(PlateCount(plate: entry.plate, count: counts[index]))
            perSideGrams += entry.plate.grams * counts[index]
        }
        return PlateLoading(
            totalWeight: Weight(grams: baseGrams + 2 * perSideGrams), perSide: plates)
    }

    /// Whether `lhs` is the better way to reach a weight than `rhs`.
    ///
    /// Fewer plates first. Both arrays are ordered heaviest denomination first, so comparing them
    /// element by element and preferring the larger count breaks a tie toward the heavier plate.
    private static func isPreferred(_ lhs: [Int], over rhs: [Int]) -> Bool {
        let lhsPlates = lhs.reduce(0, +)
        let rhsPlates = rhs.reduce(0, +)
        if lhsPlates != rhsPlates { return lhsPlates < rhsPlates }
        return lhs.lexicographicallyPrecedes(rhs, by: >)
    }

    /// `value * 2`, or `nil` if that leaves `Int`.
    private static func doubled(_ value: Int) -> Int? {
        let (result, overflowed) = value.multipliedReportingOverflow(by: 2)
        return overflowed ? nil : result
    }

    /// `lhs + rhs`, or `nil` if that leaves `Int`.
    private static func sum(_ lhs: Int, _ rhs: Int) -> Int? {
        let (result, overflowed) = lhs.addingReportingOverflow(rhs)
        return overflowed ? nil : result
    }
}
