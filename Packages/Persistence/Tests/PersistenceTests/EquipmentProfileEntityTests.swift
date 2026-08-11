import Foundation
import PowerliftingCore
import SwiftData
import Testing

@testable import Persistence

@Suite("EquipmentProfileEntity")
struct EquipmentProfileEntityTests {
    @Test("Every field survives a save and a re-read")
    func roundTrips() throws {
        let context = try makeSupportingContext()
        let inventory = try makeInventory([(10_000, 4), (25_000, 6), (1_250, 1)])
        context.insert(
            EquipmentProfileEntity(
                name: "Commercial",
                barWeightGrams: 20_000,
                collarWeightGrams: 2_500,
                inventory: inventory,
                isDefault: true
            )
        )
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<EquipmentProfileEntity>.notDeleted()).first
        )

        #expect(stored.name == "Commercial")
        #expect(stored.barWeightGrams == 20_000)
        #expect(stored.collarWeightGrams == 2_500)
        #expect(stored.isDefault)
        // PlateInventory normalises to heaviest-first, so the columns come back sorted whatever
        // order the profile was typed in — and the two arrays stay positionally paired.
        #expect(stored.plateGrams == [25_000, 10_000, 1_250])
        #expect(stored.platePairCounts == [6, 4, 1])
    }

    // Gap §14, at the seam where a factor-of-two error would actually live. FR-1.4.2 says "collar
    // weight" and does not say which; PlateCalculator loads bar + 2 × collar. Feeding this row's
    // columns straight into it is what pins that the two agree — a doc comment on either side could
    // not, and the readings differ by 2.5 kg on an empty bar here.
    @Test("Collar weight is one collar, and the calculator loads two of them")
    func collarWeightIsOneCollar() throws {
        let profile = EquipmentProfileEntity(
            name: "Meet",
            barWeightGrams: 20_000,
            collarWeightGrams: 2_500,
            inventory: try makeInventory([])
        )
        let calculator = try #require(
            PlateCalculator(
                bar: Weight(grams: profile.barWeightGrams),
                collar: Weight(grams: profile.collarWeightGrams),
                inventory: try makeInventory([])
            )
        )

        guard case .exact(let loading) = calculator.loading(for: Weight(grams: 25_000)) else {
            Issue.record("A bare bar with two collars must load exactly 25 000 g.")
            return
        }
        #expect(loading.totalWeight == Weight(grams: 25_000))

        // The other reading, spelled out so it is refused rather than merely absent: if the column
        // held the pair, the bare bar would come to 22 500 g.
        guard case .nearest(let below, let above) = calculator.loading(for: Weight(grams: 22_500))
        else {
            Issue.record("22 500 g must not load — that is the pair reading of the collar column.")
            return
        }
        #expect(below == nil)
        #expect(above?.totalWeight == Weight(grams: 25_000))
    }

    // No test that a duplicate denomination cannot reach these columns, deliberately: the only
    // writer takes a `PlateInventory`, so a duplicate cannot be constructed to hand it, which is a
    // compile-time fact rather than an assertable one. `PlateInventoryTests` owns the refusal.

    @Test("Replacing the inventory rewrites both columns together")
    func replacingTheInventoryRewritesBothColumns() throws {
        let context = try makeSupportingContext()
        let profile = EquipmentProfileEntity(
            name: "Home",
            barWeightGrams: 20_000,
            collarWeightGrams: 0,
            inventory: try makeInventory([(20_000, 2), (5_000, 3)])
        )
        context.insert(profile)
        try context.saveStamped()

        profile.replaceInventory(with: try makeInventory([(15_000, 1)]))
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<EquipmentProfileEntity>.notDeleted()).first
        )

        #expect(stored.plateGrams == [15_000])
        #expect(stored.platePairCounts == [1])
    }

    // G-6.2's citation obligation is discharged by shipping no denomination rather than by sourcing
    // one, and `init` requiring bar, collar and inventory is what enforces it — a compile-time fact
    // no test can assert. What this pins is the other half: a profile stating nothing gets nothing,
    // and no bar weight is helpfully substituted on the way in.
    @Test("A profile that states nothing holds nothing")
    func noDenominationShips() throws {
        let context = try makeSupportingContext()
        let profile = EquipmentProfileEntity(
            name: "",
            barWeightGrams: 0,
            collarWeightGrams: 0,
            inventory: try makeInventory([])
        )
        context.insert(profile)
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<EquipmentProfileEntity>.notDeleted()).first
        )

        #expect(stored.barWeightGrams == 0)
        #expect(stored.collarWeightGrams == 0)
        #expect(stored.plateGrams.isEmpty)
        #expect(stored.platePairCounts.isEmpty)
        #expect(stored.isDefault == false)
    }

    // G-2.5 forbids unique constraints and no store enforces a cross-row predicate, so "exactly one
    // default profile" is the repository's to hold (TR-0.4.3). Pinned rather than assumed, because a
    // reader would otherwise take isDefault for something the schema guarantees.
    @Test("The store accepts two profiles both claiming to be the default")
    func defaultProfileIsARepositoryInvariant() throws {
        let context = try makeSupportingContext()
        let inventory = try makeInventory([(20_000, 2)])
        for name in ["Home", "Meet"] {
            context.insert(
                EquipmentProfileEntity(
                    name: name,
                    barWeightGrams: 20_000,
                    collarWeightGrams: 2_500,
                    inventory: inventory,
                    isDefault: true
                )
            )
        }
        try context.saveStamped()

        let stored = try context.fetch(
            FetchDescriptor<EquipmentProfileEntity>.notDeleted(sortBy: [SortDescriptor(\.name)])
        )

        #expect(stored.map(\.name) == ["Home", "Meet"])
        #expect(stored.map(\.isDefault) == [true, true])
    }
}
