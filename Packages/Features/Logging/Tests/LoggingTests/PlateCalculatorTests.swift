import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-1.4.1` and `FR-1.4.4` reaching a screen. The arithmetic itself is Phase 0's and is tested
/// there exhaustively (`PlateCalculatorTests` in `PowerliftingCore`); what is under test here is the
/// layer between it and the view — which profile is loaded against, what happens when there is none
/// or the one there is cannot be used, and what the two answers say.
@Suite("Plate calculator equipment")
struct PlateCalculatorStoreTests {
    /// The metric gym every arithmetic case here runs on: a 20 kg bar and two 2.5 kg collars.
    private static let barAndCollars = Weight(grams: 25_000)

    @Test("A lifter who has set up no gym gets the empty state, not a failure")
    func noProfileIsAnEmptyState() async {
        let fakes = InMemoryRepositoryStack()
        let store = PlateCalculatorStore(repository: fakes.equipment, settings: fakes.settings)
        await store.load()

        #expect(store.hasLoaded)
        #expect(store.equipment == nil)
        // The pair that separates "no gym" from "the read failed": nothing to load against and
        // nothing to report. Anchored to the literal, since two nils satisfy any comparison.
        #expect(store.failure == nil)
        #expect(
            PlateEquipmentState.current(
                hasLoaded: store.hasLoaded, hasEquipment: false, failure: store.failure)
                == .noEquipment)
        #expect(store.loading(for: Weight(grams: 100_000)) == nil)
    }

    @Test(
        "An exactly loadable weight shows the right plates per side",
        arguments: [
            // The bare bar: an answer, not a refusal — no plates, and the weight is the base.
            (25_000, [Int]()),
            // One plate a side.
            (65_000, [20_000]),
            // Four denominations, and the case that forces the finer display step: 1.25 kg is not
            // representable at `G-3.3`'s half-kilogram.
            (102_500, [25_000, 10_000, 2_500, 1_250]),
            // Two of the heaviest, which is also the tiebreak `PlateCalculator` documents —
            // 25 + 25 + 10 rather than five 10s.
            (145_000, [25_000, 25_000, 10_000]),
        ])
    func exactLoadings(target: Int, perSide: [Int]) async throws {
        let store = try await Self.loaded()
        let result = try #require(store.loading(for: Weight(grams: target)))

        guard case .exact(let loading) = result else {
            Issue.record("\(target) g did not load exactly")
            return
        }
        #expect(loading.totalWeight == Weight(grams: target))
        #expect(Self.plates(of: loading) == perSide.map(Weight.init(grams:)))
    }

    @Test("A weight that will not load shows the nearest either side of it (FR-1.4.4)")
    func nearestBelowAndAbove() async throws {
        let store = try await Self.loaded()
        // 101 kg needs 38 kg a side; the metric set reaches 37.5 and then 38.75.
        let result = try #require(store.loading(for: Weight(grams: 101_000)))

        guard case .nearest(let below, let above) = result else {
            Issue.record("101 kg was reported as exactly loadable")
            return
        }
        #expect(below?.totalWeight == Weight(grams: 100_000))
        #expect(above?.totalWeight == Weight(grams: 102_500))
    }

    @Test("A target under the bar has nothing below it and the bare bar above")
    func lighterThanTheBar() async throws {
        let store = try await Self.loaded()
        let result = try #require(store.loading(for: Weight(grams: 10_000)))

        guard case .nearest(let below, let above) = result else {
            Issue.record("10 kg was reported as exactly loadable")
            return
        }
        #expect(below == nil)
        // Anchored to the literal rather than to another optional: `nil == nil` would satisfy the
        // comparison alone, and the guarantee under test is that this arm is *not* nil.
        #expect(above?.totalWeight == Self.barAndCollars)
        #expect(above?.perSide.isEmpty == true)
    }

    @Test("A target past what the gym stocks has nothing above it, and something below")
    func heavierThanTheInventory() async throws {
        let store = try await Self.loaded()
        // The metric set carries 153.75 kg a side, so the heaviest it loads is 332.5 kg.
        let result = try #require(store.loading(for: Weight(grams: 400_000)))

        guard case .nearest(let below, let above) = result else {
            Issue.record("400 kg was reported as exactly loadable")
            return
        }
        #expect(above == nil)
        #expect(below?.totalWeight == Weight(grams: 332_500))
    }

    @Test("Neither arm is ever empty on both sides, at any target")
    func neverBothNil() async throws {
        let store = try await Self.loaded()
        for grams in stride(from: -50_000, through: 400_000, by: 1_250) {
            guard
                case .nearest(let below, let above) = try #require(
                    store.loading(for: Weight(grams: grams)))
            else {
                continue
            }
            #expect(below != nil || above != nil, "\(grams) g resolved to neither side")
        }
    }

    @Test("The gym in use is the one every loading is worked out on")
    func aStoredProfileIsLoadedAgainst() async throws {
        let fakes = InMemoryRepositoryStack()
        let profile = Self.profile(bar: 15_000, collar: 0, plates: [10_000], pairs: [2])
        try await fakes.equipment.save(profile)
        try await fakes.equipment.makeDefault(profileID: profile.id)

        let store = PlateCalculatorStore(repository: fakes.equipment, settings: fakes.settings)
        await store.load()

        #expect(store.equipment?.profile.name == "Home gym")
        guard case .exact(let loading) = try #require(store.loading(for: Weight(grams: 35_000)))
        else {
            Issue.record("35 kg did not load on a 15 kg bar with a 10 kg pair")
            return
        }
        #expect(Self.plates(of: loading) == [Weight(grams: 10_000)])
    }

    @Test("A profile the user left unnamed is named as one, not disclaimed")
    func anUnnamedProfileIsStillTheirs() async throws {
        let fakes = InMemoryRepositoryStack()
        let profile = Self.profile(bar: 20_000, collar: 0, plates: [10_000], pairs: [1], name: "")
        try await fakes.equipment.save(profile)
        try await fakes.equipment.makeDefault(profileID: profile.id)

        let store = PlateCalculatorStore(repository: fakes.equipment, settings: fakes.settings)
        await store.load()
        let equipment = try #require(store.equipment)

        #expect(equipment.displayName == String(localized: LoggingStrings.plateEquipmentUnnamed))
    }

    @Test("A named profile is called what the user called it")
    func gymsAreNamedByWhoeverNamedThem() async throws {
        let store = try await Self.loaded()
        #expect(try #require(store.equipment).displayName == "Home gym")

        let unnamed = LoadedEquipment(
            profile: Self.profile(bar: 20_000, collar: 0, plates: [10_000], pairs: [1], name: ""),
            calculator: try #require(store.equipment).calculator
        )
        #expect(unnamed.displayName == String(localized: LoggingStrings.plateEquipmentUnnamed))
    }

    @Test("A read that failed costs the screen its equipment and offers a retry")
    func readFailure() async {
        let store = PlateCalculatorStore(
            repository: RefusingEquipment(error: .recordNotFound(id: UUID())),
            settings: InMemoryRepositoryStack().settings)
        await store.load()

        #expect(store.hasLoaded)
        #expect(store.equipment == nil)
        guard case .readFailed = store.failure else {
            Issue.record("a failed read was not reported as one")
            return
        }
        #expect(
            PlateEquipmentState.current(
                hasLoaded: store.hasLoaded, hasEquipment: false, failure: store.failure)
                == .readFailed)
    }

    @Test("A profile whose plate lists disagree is unusable rather than unreadable")
    func unusableProfile() async {
        // Two denominations and one pair count: the pairing `EquipmentProfile` documents, broken.
        // It cannot be written through `save`, which projects first — only read back from a store
        // that received it some other way, which is exactly what the projection exists for.
        let malformed = Self.profile(bar: 20_000, collar: 2_500, plates: [25_000, 20_000], pairs: [1])
        let store = PlateCalculatorStore(
            repository: StubEquipment(profile: malformed),
            settings: InMemoryRepositoryStack().settings)
        await store.load()

        #expect(store.equipment == nil)
        guard case .unusable = store.failure else {
            Issue.record("a malformed profile was not reported as unusable")
            return
        }
        #expect(
            PlateEquipmentState.current(
                hasLoaded: store.hasLoaded, hasEquipment: false, failure: store.failure)
                == .unusable)
    }

    @Test("Nothing is reported before the read answers")
    func loadingOutranksEverything() {
        #expect(
            PlateEquipmentState.current(hasLoaded: false, hasEquipment: false, failure: nil)
                == .loading)
        // Even carrying a diagnostic from a previous read: the screen must not report a failure
        // while the read that would clear it is still in flight.
        #expect(
            PlateEquipmentState.current(
                hasLoaded: false, hasEquipment: false, failure: .readFailed("stale"))
                == .loading)
        #expect(
            PlateEquipmentState.current(hasLoaded: true, hasEquipment: true, failure: nil) == .ready)
    }

    /// A store over the metric gym below, saved, marked in use, and already read.
    ///
    /// **The profile is written rather than assumed**, which is the change this task made: nothing
    /// in the app invents a gym any more, so every arithmetic case here runs on one the "user" set
    /// up — a 20 kg bar, 2.5 kg collars and a metric competition plate set.
    private static func loaded() async throws -> PlateCalculatorStore {
        let fakes = InMemoryRepositoryStack()
        let profile = Self.profile(
            bar: 20_000,
            collar: 2_500,
            plates: [25_000, 20_000, 15_000, 10_000, 5_000, 2_500, 1_250],
            pairs: [4, 1, 1, 1, 1, 1, 1]
        )
        try await fakes.equipment.save(profile)
        try await fakes.equipment.makeDefault(profileID: profile.id)
        let store = PlateCalculatorStore(repository: fakes.equipment, settings: fakes.settings)
        await store.load()
        _ = try #require(store.equipment)
        return store
    }

    /// A loading's per-side denominations, expanded one entry per plate so a count is asserted
    /// rather than trusted.
    private static func plates(of loading: PlateLoading) -> [Weight] {
        loading.perSide.flatMap { Array(repeating: $0.plate, count: $0.count) }
    }

    /// A profile record, with only the fields this suite varies.
    private static func profile(
        bar: Int,
        collar: Int,
        plates: [Int],
        pairs: [Int],
        name: String = "Home gym"
    ) -> EquipmentProfile {
        EquipmentProfile(
            id: UUID(),
            createdAt: .distantPast,
            updatedAt: .distantPast,
            deletedAt: nil,
            name: name,
            barWeight: Weight(grams: bar),
            collarWeight: Weight(grams: collar),
            plates: plates.map(Weight.init(grams:)),
            platePairCounts: pairs,
            isDefault: false
        )
    }
}

/// An equipment repository whose reads all refuse.
///
/// The failure a faithful fake will not produce: `defaultProfile()` answering `nil` is a *user* with
/// no gym, which is an empty state and not a failure at all.
struct RefusingEquipment: EquipmentRepository {
    let error: RepositoryError

    func profiles(includingDeleted: Bool) async throws -> [EquipmentProfile] { throw error }
    func profile(id: UUID, includingDeleted: Bool) async throws -> EquipmentProfile? { throw error }
    func defaultProfile() async throws -> EquipmentProfile? { throw error }
    func save(_ profile: EquipmentProfile) async throws { throw error }
    func makeDefault(profileID: UUID) async throws { throw error }
    func deleteProfile(id: UUID) async throws { throw error }
}

/// An equipment repository that hands back one record whatever is asked of it.
///
/// It exists to deliver a profile `save` would refuse — a row that arrived from a restore or from
/// CloudKit, which is the case `EquipmentProfile.inventory()` is written for.
struct StubEquipment: EquipmentRepository {
    let profile: EquipmentProfile

    func profiles(includingDeleted: Bool) async throws -> [EquipmentProfile] { [profile] }
    func profile(id: UUID, includingDeleted: Bool) async throws -> EquipmentProfile? { profile }
    func defaultProfile() async throws -> EquipmentProfile? { profile }
    func save(_ profile: EquipmentProfile) async throws {}
    func makeDefault(profileID: UUID) async throws {}
    func deleteProfile(id: UUID) async throws {}
}
