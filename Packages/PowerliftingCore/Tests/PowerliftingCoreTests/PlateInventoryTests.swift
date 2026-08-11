import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2).
//
// Construction only — what `PlateInventory` and `PlateCalculator` refuse, and why. The loading
// arithmetic is in `PlateCalculatorTests`. Every overflow case below is unreachable from a physical
// gym; they are tested directly because the guards they exercise are what let the enumeration add
// plate masses without re-checking, so a caller cannot see them and a later change could quietly
// remove them.

/// A gram figure that overflows when doubled, and the plate mass that produces it as a total.
private let halfOfInt = Int.max / 2

@Suite("Plate inventory — what it refuses")
struct PlateInventoryConstructionTests {
    @Test("An inventory of ordinary denominations is accepted and held heaviest first")
    func denominationsAreHeldHeaviestFirst() throws {
        let inventory = try plateInventory((1_250, 2), (25_000, 3), (10_000, 1))
        #expect(inventory.entries.map(\.plate.grams) == [25_000, 10_000, 1_250])
        #expect(inventory.entries.map(\.pairs) == [3, 1, 2])
    }

    @Test("The per-side total is every plate counted once")
    func totalPerSideCountsEveryPlateOnce() throws {
        let inventory = try plateInventory((25_000, 3), (10_000, 1), (1_250, 2))
        #expect(inventory.totalPerSide == Weight(grams: 87_500))
    }

    @Test("An empty inventory is a real profile, not a refusal")
    func anEmptyInventoryIsAccepted() throws {
        let inventory = try #require(PlateInventory(entries: []))
        #expect(inventory.entries.isEmpty)
        #expect(inventory.totalPerSide == Weight.zero)
    }

    @Test("A plate lighter than a gram is refused", arguments: [0, -1, -25_000])
    func aPlateUnderOneGramIsRefused(grams: Int) {
        let entry = PlateInventory.Entry(plate: Weight(grams: grams), pairs: 2)
        #expect(PlateInventory(entries: [entry]) == nil)
        // The same entry with a legal plate mass constructs, so the refusal is the mass and not
        // something else about the entry.
        #expect(PlateInventory(entries: [PlateInventory.Entry(plate: Weight(grams: 25_000), pairs: 2)]) != nil)
    }

    @Test("A negative pair count is refused")
    func aNegativePairCountIsRefused() {
        let entry = PlateInventory.Entry(plate: Weight(grams: 25_000), pairs: -1)
        #expect(PlateInventory(entries: [entry]) == nil)
    }

    @Test("Zero pairs is legal — a profile may list a denomination the gym is out of")
    func zeroPairsIsLegal() throws {
        let inventory = try plateInventory((25_000, 0))
        #expect(inventory.totalPerSide == Weight.zero)
        #expect(inventory.entries.count == 1)
    }

    @Test("A denomination listed twice is refused rather than summed")
    func aDuplicateDenominationIsRefused() {
        let entries = [
            PlateInventory.Entry(plate: Weight(grams: 20_000), pairs: 1),
            PlateInventory.Entry(plate: Weight(grams: 20_000), pairs: 2),
        ]
        #expect(PlateInventory(entries: entries) == nil)
        // Summed, this would have been a legal four-pair inventory — which is exactly why the
        // duplicate is refused instead: a repeated row is far likelier a mistake than a statement.
        #expect(
            PlateInventory(entries: [PlateInventory.Entry(plate: Weight(grams: 20_000), pairs: 3)])
                != nil)
    }

    @Test("A denomination whose pairs overflow their own mass is refused")
    func aDenominationOverflowingItsMassIsRefused() {
        let entry = PlateInventory.Entry(plate: Weight(grams: .max), pairs: 2)
        #expect(PlateInventory(entries: [entry]) == nil)
    }

    @Test("An inventory whose denominations overflow in sum is refused")
    func anInventoryOverflowingInSumIsRefused() {
        let entries = [
            PlateInventory.Entry(plate: Weight(grams: .max), pairs: 1),
            PlateInventory.Entry(plate: Weight(grams: .max - 1), pairs: 1),
        ]
        #expect(PlateInventory(entries: entries) == nil)
    }
}

@Suite("Plate calculator — what it refuses to be built with")
struct PlateCalculatorConstructionTests {
    @Test("A bar and collar of ordinary mass are accepted")
    func anOrdinaryProfileIsAccepted() throws {
        let calculator = try plateCalculator(
            bar: 20_000, collar: 2_500, inventory: try PlateSets.competition())
        #expect(calculator.bar == Weight(grams: 20_000))
        #expect(calculator.collar == Weight(grams: 2_500))
        #expect(calculator.inventory.totalPerSide == Weight(grams: 129_500))
    }

    @Test("A negative bar is refused")
    func aNegativeBarIsRefused() throws {
        let inventory = try PlateSets.homeGym()
        #expect(PlateCalculator(bar: Weight(grams: -1), collar: .zero, inventory: inventory) == nil)
    }

    @Test("A negative collar is refused")
    func aNegativeCollarIsRefused() throws {
        let inventory = try PlateSets.homeGym()
        #expect(
            PlateCalculator(bar: Weight(grams: 20_000), collar: Weight(grams: -1), inventory: inventory)
                == nil)
    }

    @Test("A collar that overflows when both are counted is refused")
    func aCollarOverflowingWhenDoubledIsRefused() throws {
        let inventory = try #require(PlateInventory(entries: []))
        #expect(
            PlateCalculator(bar: .zero, collar: Weight(grams: .max), inventory: inventory) == nil)
    }

    @Test("A bar that overflows once its collars are added is refused")
    func aBarOverflowingWithItsCollarsIsRefused() throws {
        let inventory = try #require(PlateInventory(entries: []))
        #expect(
            PlateCalculator(bar: Weight(grams: .max), collar: Weight(grams: 1), inventory: inventory)
                == nil)
    }

    @Test("An inventory that overflows across both sides is refused")
    func anInventoryOverflowingAcrossBothSidesIsRefused() throws {
        let inventory = try plateInventory((Int.max, 1))
        #expect(PlateCalculator(bar: .zero, collar: .zero, inventory: inventory) == nil)
    }

    @Test("A profile whose heaviest possible load overflows is refused")
    func aProfileWhoseHeaviestLoadOverflowsIsRefused() throws {
        // Twice the inventory fits, and the bar does too — only their sum does not.
        let inventory = try plateInventory((halfOfInt, 1))
        #expect(PlateCalculator(bar: .zero, collar: .zero, inventory: inventory) != nil)
        #expect(PlateCalculator(bar: Weight(grams: 100), collar: .zero, inventory: inventory) == nil)
    }
}
