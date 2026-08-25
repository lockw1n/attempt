import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-1.4.3` and `FR-1.10.3` as operations rather than as a screen: which gym is in use, what a
/// second one does to a loading, and what deleting one costs.
@Suite("Equipment profiles")
struct EquipmentProfilesStateTests {
    /// The locale every draft here is typed in.
    private static let locale = Locale(identifier: "en_US_POSIX")

    @Test("The first gym a user sets up becomes the one in use")
    func theFirstProfileBecomesTheDefault() async throws {
        // The clause that makes a first profile usable at all: `save` deliberately refuses to write
        // `isDefault`, so without it the gym would be stored and loaded against by nothing.
        let fakes = InMemoryRepositoryStack()
        let state = EquipmentProfilesState(repository: fakes.equipment)
        await state.load()

        #expect(EquipmentProfilesScreenState.current(state.phase) == .empty)
        #expect(
            await state.save(
                Self.draft(name: "Home gym", bar: "20", collar: "2.5"),
                replacing: nil))

        #expect(state.profiles.count == 1)
        #expect(state.activeProfileID == state.profiles.first?.id)
        #expect(try await fakes.equipment.defaultProfile()?.name == "Home gym")
    }

    @Test("A second gym does not take over from the first")
    func aSecondProfileDoesNotStealTheFlag() async throws {
        let fakes = InMemoryRepositoryStack()
        let state = EquipmentProfilesState(repository: fakes.equipment)
        await state.load()
        await state.save(Self.draft(name: "Home gym", bar: "20", collar: "2.5"), replacing: nil)
        let first = try #require(state.activeProfileID)

        await state.save(Self.draft(name: "The meet", bar: "20", collar: "0"), replacing: nil)

        #expect(state.profiles.count == 2)
        #expect(state.activeProfileID == first)
    }

    @Test("Switching gyms changes what the calculator loads")
    func switchingProfilesChangesTheLoading() async throws {
        // FR-1.4.3's whole point, end to end: two profiles whose bar, collars and plates differ, and
        // a target that loads differently on each.
        let fakes = InMemoryRepositoryStack()
        let state = EquipmentProfilesState(repository: fakes.equipment)
        await state.load()
        await state.save(
            Self.draft(name: "Home gym", bar: "20", collar: "2.5", plates: [("25", "2")]),
            replacing: nil)
        await state.save(
            Self.draft(name: "The meet", bar: "25", collar: "0", plates: [("20", "2")]),
            replacing: nil)

        let store = PlateCalculatorStore(repository: fakes.equipment, settings: fakes.settings)
        await store.load()
        #expect(store.equipment?.profile.name == "Home gym")
        // 75 kg on the home bar: 20 + 2 × 2.5 = 25 base, 25 kg a side.
        guard case .exact(let home) = try #require(store.loading(for: Weight(grams: 75_000))) else {
            Issue.record("75 kg did not load on the home gym")
            return
        }
        #expect(home.perSide.map(\.plate) == [Weight(grams: 25_000)])

        let meet = try #require(state.profiles.first { $0.name == "The meet" })
        await state.makeActive(meet.id)
        await store.load()

        #expect(store.equipment?.profile.name == "The meet")
        // The same 75 kg on the meet bar: 25 base and no collars, so 25 kg a side is out of reach —
        // the meet gym only stocks 20s, and 65 kg is the nearest below.
        guard case .nearest(let below, _) = try #require(store.loading(for: Weight(grams: 75_000)))
        else {
            Issue.record("75 kg loaded exactly on a gym that stocks one pair of 20s")
            return
        }
        #expect(below?.totalWeight == Weight(grams: 65_000))
    }

    @Test("Deleting a gym that is not in use leaves the loading alone")
    func deletingANonActiveProfileChangesNothing() async throws {
        let fakes = InMemoryRepositoryStack()
        let state = EquipmentProfilesState(repository: fakes.equipment)
        await state.load()
        await state.save(
            Self.draft(name: "Home gym", bar: "20", collar: "2.5", plates: [("25", "2")]),
            replacing: nil)
        await state.save(Self.draft(name: "The meet", bar: "25", collar: "0"), replacing: nil)
        let active = try #require(state.activeProfileID)
        let other = try #require(state.profiles.first { $0.id != active })

        await state.delete(other.id)

        #expect(state.writeFailure == nil)
        #expect(state.profiles.map(\.id) == [active])
        #expect(state.activeProfileID == active)

        let store = PlateCalculatorStore(repository: fakes.equipment, settings: fakes.settings)
        await store.load()
        #expect(store.equipment?.profile.name == "Home gym")
    }

    @Test("Deleting the gym in use leaves none in use, and the calculator says so")
    func deletingTheActiveProfileEmptiesTheCalculator() async throws {
        // The repository promotes nothing, deliberately, and this screen does not repair that: what
        // it must not do is crash or claim a gym that is gone.
        let fakes = InMemoryRepositoryStack()
        let state = EquipmentProfilesState(repository: fakes.equipment)
        await state.load()
        await state.save(Self.draft(name: "Home gym", bar: "20", collar: "2.5"), replacing: nil)
        await state.save(Self.draft(name: "The meet", bar: "25", collar: "0"), replacing: nil)
        let active = try #require(state.activeProfileID)

        await state.delete(active)

        #expect(state.activeProfileID == nil)
        #expect(state.profiles.count == 1)
        #expect(EquipmentProfilesScreenState.current(state.phase) == .ready)

        let store = PlateCalculatorStore(repository: fakes.equipment, settings: fakes.settings)
        await store.load()
        #expect(store.equipment == nil)
        #expect(store.failure == nil)
        #expect(
            PlateEquipmentState.current(
                hasLoaded: store.hasLoaded, hasEquipment: false, failure: store.failure)
                == .noEquipment)
        // And one tap puts it right, which is what makes leaving no default recoverable.
        await state.makeActive(try #require(state.profiles.first).id)
        await store.load()
        #expect(store.equipment?.profile.name == "The meet")
    }

    @Test("An edit keeps the gym in use, and reaches the next loading")
    func editingTheActiveProfileKeepsIt() async throws {
        let fakes = InMemoryRepositoryStack()
        let state = EquipmentProfilesState(repository: fakes.equipment)
        await state.load()
        await state.save(
            Self.draft(name: "Home gym", bar: "20", collar: "2.5", plates: [("25", "2")]),
            replacing: nil)
        let stored = try #require(state.profiles.first)

        await state.save(
            Self.draft(name: "Home gym", bar: "20", collar: "0", plates: [("25", "2")]),
            replacing: stored)

        #expect(state.profiles.count == 1)
        #expect(state.activeProfileID == stored.id)
        let store = PlateCalculatorStore(repository: fakes.equipment, settings: fakes.settings)
        await store.load()
        #expect(store.equipment?.calculator.collar == .zero)
    }

    @Test("A read that failed is reported as one, and retried")
    func readFailure() async {
        let state = EquipmentProfilesState(
            repository: RefusingEquipment(error: .recordNotFound(id: UUID())))
        await state.load()

        #expect(EquipmentProfilesScreenState.current(state.phase) == .failed)
        #expect(state.profiles.isEmpty)
        #expect(state.activeProfileID == nil)
    }

    @Test("A write that failed keeps the list and reports itself")
    func writeFailureKeepsTheScreen() async throws {
        let fakes = InMemoryRepositoryStack()
        let state = EquipmentProfilesState(repository: fakes.equipment)
        await state.load()
        await state.save(Self.draft(name: "Home gym", bar: "20", collar: "0"), replacing: nil)

        // A denomination repeated in the record rather than in the form: the repository projects
        // before it writes, and this is the refusal a screen has to survive.
        let malformed = EquipmentProfile(
            id: UUID(),
            createdAt: .distantPast,
            updatedAt: .distantPast,
            deletedAt: nil,
            name: "Broken",
            barWeight: Weight(grams: 20_000),
            collarWeight: .zero,
            plates: [Weight(grams: 20_000), Weight(grams: 20_000)],
            platePairCounts: [1, 1],
            isDefault: false
        )
        await #expect(throws: RepositoryError.self) { try await fakes.equipment.save(malformed) }

        await state.delete(UUID())

        #expect(state.writeFailure != nil)
        // The list is still there, which is what makes the next attempt a tap rather than a relaunch.
        #expect(state.profiles.count == 1)
        #expect(EquipmentProfilesScreenState.current(state.phase) == .ready)
    }

    @Test("Nothing is reported before the read answers")
    func loadingOutranksEverything() {
        #expect(EquipmentProfilesScreenState.current(.idle) == .loading)
        #expect(EquipmentProfilesScreenState.current(.loading) == .loading)
        #expect(EquipmentProfilesScreenState.current(.loaded([])) == .empty)
        #expect(EquipmentProfilesScreenState.current(.failed("why")) == .failed)
    }

    /// A draft as the editor would hold it.
    ///
    /// - Parameters:
    ///   - name: What the gym is called.
    ///   - bar: The bar's mass, as typed.
    ///   - collar: One collar's mass, as typed.
    ///   - plates: The denominations, each with its pair count, as typed.
    /// - Returns: The draft.
    private static func draft(
        name: String,
        bar: String,
        collar: String,
        plates: [(String, String)] = []
    ) -> EquipmentProfileDraft {
        var draft = EquipmentProfileDraft(unit: .kilograms, locale: locale)
        draft.name = name
        draft.barText = bar
        draft.collarText = collar
        draft.plates = plates.map { PlateDraft(weightText: $0.0, pairsText: $0.1) }
        return draft
    }
}
