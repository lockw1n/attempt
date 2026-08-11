import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2).
//
// ## What "published reference values" means here (G-6.2)
//
// Plate maths is a different kind of claim from an e1RM equation. Epley's coefficient is 1/30
// because Epley published it and there is nothing to derive it from, so it needs a citation. A
// plate loading is a *consequence* of the inventory: given the denominations, arithmetic fixes the
// answer, and nothing anyone could publish would be independent of that arithmetic. So the
// evidence here is of a different shape, in three parts:
//
//   1. Two invariants asserted on every loading this file receives — `total == bar + 2 × collar +
//      2 × Σ(plate × count)`, and no denomination used more than the inventory holds. Both are
//      checkable by hand from the numbers printed in a failure.
//   2. `achievablePerSideSums` — an independent implementation. It is exponential, unpruned and
//      has no cap, no tie-break and no reconstruction, so it shares no mechanism with the bounded
//      enumeration under test. The sweeps below require the calculator to agree with it on every
//      target, which is a stronger guarantee than a citation could give.
//   3. Expected per-side lists in the parameterized tables are arithmetic anyone can redo, and
//      each is cross-checked for minimality against (2) rather than taken from a run of the code.
//
// **The competition denominations below are a test input and carry no product claim.** They are
// the set in wide circulation, not verified against the IPF technical rules, and deliberately not
// shipped: `FR-1.4.2` and `FR-1.4.3` make inventory user-configured and per-profile, so nothing in
// `Sources/` states a plate list. If these denominations are wrong, this file merely describes a
// different gym and every invariant above still holds — which is exactly why an uncited list is
// tolerable here and was not tolerable for the RPE chart, where the numbers ship and reach a
// lifter.

// MARK: - Fixtures

/// Builds an inventory from gram/pair pairs, failing the test rather than force unwrapping
/// (`force_unwrapping` is banned by `.swiftlint.yml`).
func plateInventory(_ entries: (grams: Int, pairs: Int)...) throws -> PlateInventory {
    try #require(
        PlateInventory(
            entries: entries.map {
                PlateInventory.Entry(plate: Weight(grams: $0.grams), pairs: $0.pairs)
            }))
}

/// Builds a calculator, failing the test rather than force unwrapping.
func plateCalculator(bar: Int, collar: Int = 0, inventory: PlateInventory) throws -> PlateCalculator {
    try #require(
        PlateCalculator(
            bar: Weight(grams: bar), collar: Weight(grams: collar), inventory: inventory))
}

/// The two inventories the scope names, plus the bar and collar masses that go with each.
enum PlateSets {
    /// The denominations in wide competition use. See this file's header: a test input, uncited
    /// on purpose, and not shipped anywhere in `Sources/`.
    static func competition() throws -> PlateInventory {
        try plateInventory(
            (25_000, 3),
            (20_000, 1),
            (15_000, 1),
            (10_000, 1),
            (5_000, 1),
            (2_500, 1),
            (1_250, 1),
            (500, 1),
            (250, 1))
    }

    /// A sparse home gym: one pair of 20s, two pairs of 15s, one pair of 5s, two pairs of 1.25s.
    ///
    /// Chosen so that taking the heaviest plate that fits gives the wrong answer — see
    /// `takingTheHeaviestPlateThatFitsWouldMissAnExactLoad`.
    static func homeGym() throws -> PlateInventory {
        try plateInventory((20_000, 1), (15_000, 2), (5_000, 1), (1_250, 2))
    }
}

/// One row of an expected-loading table.
struct PlateLoadingCase: Sendable {
    let target: Int
    let perSide: [PlateCount]

    init(_ target: Int, _ perSide: [(Int, Int)]) {
        self.target = target
        self.perSide = perSide.map { PlateCount(plate: Weight(grams: $0.0), count: $0.1) }
    }
}

// MARK: - The independent reference

/// Every per-side plate sum this inventory can make, mapped to the fewest plates that make it.
///
/// Full recursive enumeration of every count vector — no dynamic programming, no cap, no pruning.
/// It shares no mechanism with `PlateCalculator`'s bounded enumeration, which is the point: a
/// reference that reproduced the same algorithm would agree with it while both were wrong. The
/// fixtures are sized so this stays cheap (1024 vectors for the competition set, 36 for the home
/// gym).
private func achievablePerSideSums(_ inventory: PlateInventory) -> [Int: Int] {
    var sums: [Int: Int] = [:]
    func walk(_ index: Int, _ sum: Int, _ plates: Int) {
        guard index < inventory.entries.count else {
            if let existing = sums[sum], existing <= plates { return }
            sums[sum] = plates
            return
        }
        let entry = inventory.entries[index]
        for used in 0...entry.pairs {
            walk(index + 1, sum + entry.plate.grams * used, plates + used)
        }
    }
    walk(0, 0, 0)
    return sums
}

/// Asserts the two invariants, and that the loading uses as few plates as the reference can.
private func expectConsistent(
    _ loading: PlateLoading,
    base: Int,
    inventory: PlateInventory,
    minimumPlates: [Int: Int],
    _ comment: Comment
) throws {
    var perSideGrams = 0
    var plates = 0
    var previous: Weight?
    for used in loading.perSide {
        #expect(used.count >= 1, comment)
        let stocked = try #require(inventory.entries.first { $0.plate == used.plate }, comment)
        #expect(used.count <= stocked.pairs, comment)
        if let previous { #expect(used.plate < previous, comment) }
        previous = used.plate
        perSideGrams += used.plate.grams * used.count
        plates += used.count
    }
    #expect(loading.totalWeight.grams == base + 2 * perSideGrams, comment)
    #expect(minimumPlates[perSideGrams] == plates, comment)
}

/// Requires the calculator to agree with `achievablePerSideSums` on every target in `targets`.
private func expectMatchesExhaustiveSearch(
    bar: Int, collar: Int = 0, inventory: PlateInventory, targets: [Int]
) throws {
    let calculator = try plateCalculator(bar: bar, collar: collar, inventory: inventory)
    let base = bar + 2 * collar
    let minimumPlates = achievablePerSideSums(inventory)
    let totals = minimumPlates.keys.map { base + 2 * $0 }.sorted()

    for target in targets {
        let comment = Comment(rawValue: "target \(target) g")
        let expectedBelow = totals.last { $0 <= target }
        let expectedAbove = totals.first { $0 >= target }

        switch calculator.loading(for: Weight(grams: target)) {
        case .exact(let loading):
            #expect(loading.totalWeight.grams == target, comment)
            #expect(expectedBelow == target, comment)
            #expect(expectedAbove == target, comment)
            try expectConsistent(
                loading, base: base, inventory: inventory, minimumPlates: minimumPlates, comment)

        case .nearest(let below, let above):
            // An exactly loadable target must never arrive here wearing two equal arms.
            #expect(expectedBelow != target, comment)
            #expect(expectedAbove != target, comment)
            // Never both nil — the bar carrying nothing is always loadable, so it is either side.
            #expect(below != nil || above != nil, comment)

            // Each arm is anchored against a literal from the reference rather than compared
            // optional-to-optional, which would pass whenever both sides happened to be nil.
            if let expectedBelow {
                let loading = try #require(below, comment)
                #expect(loading.totalWeight.grams == expectedBelow, comment)
                try expectConsistent(
                    loading, base: base, inventory: inventory, minimumPlates: minimumPlates, comment)
            } else {
                #expect(below == nil, comment)
            }
            if let expectedAbove {
                let loading = try #require(above, comment)
                #expect(loading.totalWeight.grams == expectedAbove, comment)
                try expectConsistent(
                    loading, base: base, inventory: inventory, minimumPlates: minimumPlates, comment)
            } else {
                #expect(above == nil, comment)
            }
        }
    }
}

// MARK: - A standard competition set

@Suite("Plate calculator — a 20 kg competition set")
struct PlateCalculatorCompetitionTests {
    /// Every row is `20 000 + 2 × 2 500 + 2 × Σ(plate × count)`, redoable by hand. Minimality of
    /// each list is separately cross-checked against the exhaustive reference by
    /// `expectConsistent`, so a shorter loading than the one named here fails.
    @Test(
        "The canonical attempt weights load exactly",
        arguments: [
            PlateLoadingCase(25_000, []),
            PlateLoadingCase(60_000, [(15_000, 1), (2_500, 1)]),
            PlateLoadingCase(100_000, [(25_000, 1), (10_000, 1), (2_500, 1)]),
            PlateLoadingCase(137_500, [(25_000, 2), (5_000, 1), (1_250, 1)]),
            PlateLoadingCase(202_500, [(25_000, 3), (10_000, 1), (2_500, 1), (1_250, 1)]),
            PlateLoadingCase(227_500, [(25_000, 3), (20_000, 1), (5_000, 1), (1_250, 1)]),
        ])
    func canonicalAttemptsLoadExactly(_ testCase: PlateLoadingCase) throws {
        let inventory = try PlateSets.competition()
        let calculator = try plateCalculator(bar: 20_000, collar: 2_500, inventory: inventory)
        guard case .exact(let loading) = calculator.loading(for: Weight(grams: testCase.target)) else {
            Issue.record("\(testCase.target) g should load exactly")
            return
        }
        #expect(loading.totalWeight == Weight(grams: testCase.target))
        #expect(loading.perSide == testCase.perSide)
        try expectConsistent(
            loading,
            base: 25_000,
            inventory: inventory,
            minimumPlates: achievablePerSideSums(inventory),
            "")
    }

    @Test("The bar and its collars are a loading, carrying no plates")
    func barAndCollarsAloneIsALoading() throws {
        let calculator = try plateCalculator(
            bar: 20_000, collar: 2_500, inventory: try PlateSets.competition())
        guard case .exact(let loading) = calculator.loading(for: Weight(grams: 25_000)) else {
            Issue.record("bar plus collars should load exactly")
            return
        }
        #expect(loading.totalWeight == Weight(grams: 25_000))
        #expect(loading.perSide.isEmpty)
    }

    @Test("A tie on plate count is broken toward the heavier plate")
    func tiesPreferTheHeavierPlate() throws {
        let calculator = try plateCalculator(
            bar: 20_000, collar: 2_500, inventory: try PlateSets.competition())
        // 37.5 kg a side is 25 + 10 + 2.5 or 20 + 15 + 2.5 — three plates either way.
        guard case .exact(let loading) = calculator.loading(for: Weight(grams: 100_000)) else {
            Issue.record("100 kg should load exactly")
            return
        }
        #expect(loading.perSide.first?.plate == Weight(grams: 25_000))
    }
}

// MARK: - A sparse home gym

@Suite("Plate calculator — a sparse inventory")
struct PlateCalculatorSparseInventoryTests {
    @Test("Taking the heaviest plate that fits would miss an exact load")
    func takingTheHeaviestPlateThatFitsWouldMissAnExactLoad() throws {
        let calculator = try plateCalculator(bar: 20_000, inventory: try PlateSets.homeGym())
        // 30 kg a side. Heaviest-first takes the 20, leaving 10 kg that no 15 fits into, and ends
        // at 20 + 5 + 1.25 + 1.25 = 27.5 kg a side — a 75 kg bar, reported as the nearest below.
        // Two 15s make 30 kg exactly.
        guard case .exact(let loading) = calculator.loading(for: Weight(grams: 80_000)) else {
            Issue.record("80 kg loads as 15 + 15 a side")
            return
        }
        #expect(loading.totalWeight == Weight(grams: 80_000))
        #expect(loading.perSide == [PlateCount(plate: Weight(grams: 15_000), count: 2)])
        #expect(loading.totalWeight.grams > 75_000)
    }

    @Test("A pair count that runs out mid-load bounds the answer")
    func exhaustedPairsBoundTheLoad() throws {
        let calculator = try plateCalculator(bar: 20_000, inventory: try PlateSets.homeGym())
        // 45 kg a side is three 15s, and the gym owns two pairs. Nothing else reaches 45.
        guard case .nearest(let below, let above) = calculator.loading(for: Weight(grams: 110_000)) else {
            Issue.record("110 kg is not loadable with two pairs of 15s")
            return
        }
        let under = try #require(below)
        let over = try #require(above)
        #expect(under.totalWeight == Weight(grams: 105_000))
        #expect(over.totalWeight == Weight(grams: 120_000))
        // The heavier answer uses both pairs of 15s and no more.
        #expect(over.perSide.contains(PlateCount(plate: Weight(grams: 15_000), count: 2)))
    }

    @Test("A target beyond the whole inventory has nothing above it")
    func aTargetBeyondTheInventoryHasNothingAbove() throws {
        let calculator = try plateCalculator(bar: 20_000, inventory: try PlateSets.homeGym())
        guard case .nearest(let below, let above) = calculator.loading(for: Weight(grams: 500_000)) else {
            Issue.record("500 kg is not loadable in a home gym")
            return
        }
        #expect(above == nil)
        // 20 + 2 × (20 + 15 + 15 + 5 + 1.25 + 1.25) — every plate in the gym.
        #expect(try #require(below).totalWeight == Weight(grams: 135_000))
    }

    @Test("A denomination stocked zero pairs deep is not loaded")
    func aDenominationWithNoPairsIsNotLoaded() throws {
        let inventory = try plateInventory((20_000, 0), (10_000, 1))
        let calculator = try plateCalculator(bar: 20_000, inventory: inventory)
        guard case .exact(let loading) = calculator.loading(for: Weight(grams: 40_000)) else {
            Issue.record("40 kg loads as one 10 a side")
            return
        }
        #expect(loading.perSide == [PlateCount(plate: Weight(grams: 10_000), count: 1)])
    }

    @Test("A bar with no plates at all loads exactly one weight")
    func anEmptyInventoryLoadsOneWeight() throws {
        let calculator = try plateCalculator(bar: 20_000, inventory: try #require(PlateInventory(entries: [])))
        guard case .exact(let loading) = calculator.loading(for: Weight(grams: 20_000)) else {
            Issue.record("the bar alone loads exactly")
            return
        }
        #expect(loading.perSide.isEmpty)
        guard case .nearest(let below, let above) = calculator.loading(for: Weight(grams: 60_000)) else {
            Issue.record("60 kg is not loadable with no plates")
            return
        }
        #expect(above == nil)
        #expect(try #require(below).totalWeight == Weight(grams: 20_000))
    }
}

// MARK: - Below the bar, and the odd gram

@Suite("Plate calculator — targets the bar cannot bracket")
struct PlateCalculatorBoundaryTests {
    @Test("A target under the bar has nothing below it and the bare bar above")
    func aTargetUnderTheBarHasNothingBelow() throws {
        let calculator = try plateCalculator(
            bar: 20_000, collar: 2_500, inventory: try PlateSets.competition())
        guard case .nearest(let below, let above) = calculator.loading(for: Weight(grams: 10_000)) else {
            Issue.record("10 kg is lighter than the bar and its collars")
            return
        }
        #expect(below == nil)
        let over = try #require(above)
        #expect(over.totalWeight == Weight(grams: 25_000))
        #expect(over.perSide.isEmpty)
    }

    @Test("A negative target behaves the same way")
    func aNegativeTargetHasNothingBelow() throws {
        let calculator = try plateCalculator(bar: 20_000, inventory: try PlateSets.homeGym())
        guard case .nearest(let below, let above) = calculator.loading(for: Weight(grams: -5_000)) else {
            Issue.record("a negative target is lighter than the bar")
            return
        }
        #expect(below == nil)
        #expect(try #require(above).totalWeight == Weight(grams: 20_000))
    }

    @Test("A target so light that subtracting the bar overflows is still answered")
    func anExtremeNegativeTargetDoesNotTrap() throws {
        let calculator = try plateCalculator(
            bar: 20_000, collar: 2_500, inventory: try PlateSets.competition())
        guard case .nearest(let below, let above) = calculator.loading(for: Weight(grams: .min)) else {
            Issue.record("Int.min is lighter than the bar")
            return
        }
        #expect(below == nil)
        #expect(try #require(above).totalWeight == Weight(grams: 25_000))
    }

    @Test("An odd gram is not loadable and is not silently truncated")
    func anOddGramIsNotLoadable() throws {
        // Every loading is bar + 2 × (per-side sum), so an odd remainder cannot be split evenly
        // across the two sides however fine the plates are.
        let calculator = try plateCalculator(bar: 20_000, inventory: try plateInventory((500, 2)))
        guard case .nearest(let below, let above) = calculator.loading(for: Weight(grams: 20_001)) else {
            Issue.record("20 001 g cannot be split across two sides")
            return
        }
        #expect(try #require(below).totalWeight == Weight(grams: 20_000))
        #expect(try #require(above).totalWeight == Weight(grams: 21_000))
    }
}

// MARK: - The exhaustive cross-check (G-6.2)

@Suite("Plate calculator — agreement with an exhaustive search")
struct PlateCalculatorExhaustiveTests {
    @Test("Every 2.5 kg target across a competition set's whole range")
    func competitionSetAcrossItsRange() throws {
        try expectMatchesExhaustiveSearch(
            bar: 20_000,
            collar: 2_500,
            inventory: try PlateSets.competition(),
            targets: Array(stride(from: 0, through: 290_000, by: 2_500)))
    }

    @Test("Every 250 g target through the band a lifter works in")
    func competitionSetAtTheFinestStep() throws {
        try expectMatchesExhaustiveSearch(
            bar: 20_000,
            collar: 2_500,
            inventory: try PlateSets.competition(),
            targets: Array(stride(from: 95_000, through: 110_000, by: 250)))
    }

    @Test("Every 1.25 kg target across a sparse gym's whole range")
    func homeGymAcrossItsRange() throws {
        try expectMatchesExhaustiveSearch(
            bar: 20_000,
            inventory: try PlateSets.homeGym(),
            targets: Array(stride(from: 0, through: 140_000, by: 1_250)))
    }

    @Test("Every single gram either side of a loadable weight")
    func everyGramAroundALoadableWeight() throws {
        try expectMatchesExhaustiveSearch(
            bar: 20_000,
            inventory: try plateInventory((500, 2)),
            targets: Array(19_990...21_010))
    }
}
