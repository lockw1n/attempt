import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData
import Testing

@testable import Persistence

@Suite("EquipmentRepository over SwiftData")
struct EquipmentRepositoryTests {
    @Test("Profiles come back in name order")
    func profilesAreNameOrdered() async throws {
        let stack = try RepositoryHarness().stack
        for name in ["Powerlifting club", "Attic", "Hotel"] {
            try await stack.equipment.save(profileRecord(name: name))
        }

        #expect(
            try await stack.equipment.profiles(includingDeleted: false).map(\.name)
                == ["Attic", "Hotel", "Powerlifting club"])
    }

    @Test("A save never writes isDefault, whatever the record carries")
    func aSaveDoesNotHonourTheFlag() async throws {
        let stack = try RepositoryHarness().stack
        let held = profileRecord(name: "A")
        try await stack.equipment.save(held)
        try await stack.equipment.makeDefault(profileID: held.id)

        // The insert path: init(record:) writes the flag, so the save has to clear it.
        let claimant = profileRecord(name: "B", isDefault: true)
        try await stack.equipment.save(claimant)
        #expect(try await stack.equipment.defaultProfile()?.id == held.id)

        // And the update path.
        try await stack.equipment.save(profileRecord(id: claimant.id, name: "B", isDefault: true))
        #expect(try await stack.equipment.defaultProfile()?.id == held.id)
    }

    @Test("makeDefault clears every other profile in the same write")
    func makingADefaultClearsTheRest() async throws {
        let harness = try RepositoryHarness()
        let stack = harness.stack
        let first = profileRecord(name: "A")
        let second = profileRecord(name: "B")
        let third = profileRecord(name: "C")
        for profile in [first, second, third] { try await stack.equipment.save(profile) }

        try await stack.equipment.makeDefault(profileID: first.id)
        try await stack.equipment.makeDefault(profileID: third.id)

        #expect(try await stack.equipment.defaultProfile()?.id == third.id)
        let flagged = try harness.store()
            .fetch(FetchDescriptor<EquipmentProfileEntity>())
            .filter(\.isDefault)
        #expect(flagged.map(\.id) == [third.id])
    }

    @Test("makeDefault does not restamp a profile whose flag did not move")
    func makeDefaultWritesOnlyWhatItChanges() async throws {
        // Assigning a `@Model` property marks the row changed whatever the value was, so an
        // unconditional loop restamps `updatedAt` on every profile in the store — and `updatedAt`
        // is `G-2.4`'s conflict key, so a no-op local write outranks a real remote edit.
        let harness = try RepositoryHarness()
        let stack = harness.stack
        let target = profileRecord(name: "A")
        let bystander = profileRecord(name: "B")
        try await stack.equipment.save(target)
        try await stack.equipment.save(bystander)

        func stamp(of id: UUID) throws -> Date? {
            try harness.store()
                .fetch(FetchDescriptor<EquipmentProfileEntity>())
                .first { $0.id == id }?.updatedAt
        }
        let before = try #require(try stamp(of: bystander.id))
        try await Task.sleep(nanoseconds: 20_000_000)

        try await stack.equipment.makeDefault(profileID: target.id)

        #expect(try stamp(of: bystander.id) == before)
        // The row that did move is stamped, which is what says the check is not just "write less".
        #expect(try stamp(of: target.id) ?? .distantPast > before)
    }

    @Test("makeDefault refuses a profile that is not there")
    func makingAMissingProfileDefaultIsRefused() async throws {
        let stack = try RepositoryHarness().stack
        let absent = UUID()

        await #expect(throws: RepositoryError.recordNotFound(id: absent)) {
            try await stack.equipment.makeDefault(profileID: absent)
        }
        await #expect(throws: RepositoryError.recordNotFound(id: absent)) {
            try await stack.equipment.deleteProfile(id: absent)
        }
    }

    @Test("A save refuses each way the two plate lists can fail, and stores nothing")
    func everyInventoryRefusalReachesTheSave() async throws {
        let harness = try RepositoryHarness()
        let refused = [
            profileRecord(plates: [25_000, 25_000], pairCounts: [2, 2]),
            profileRecord(plates: [25_000, 20_000], pairCounts: [2, -1]),
            profileRecord(plates: [25_000, 20_000], pairCounts: [2]),
        ]

        for profile in refused {
            await #expect(throws: RepositoryError.self) {
                try await harness.stack.equipment.save(profile)
            }
        }

        #expect(try harness.store().fetch(FetchDescriptor<EquipmentProfileEntity>()).isEmpty)
    }
}

@Suite("BodyweightRepository over SwiftData")
struct BodyweightRepositoryTests {
    @Test("Readings in a range come back newest first, and the range is not widened")
    func readingsAreRangedAndOrdered() async throws {
        let stack = try RepositoryHarness().stack
        let day = 86_400.0
        let base = Date(timeIntervalSince1970: 1_600_000_000)
        for offset in 0..<4 {
            try await stack.bodyweight.save(
                bodyweightRecord(date: base + Double(offset) * day, grams: 80_000 + offset))
        }

        let read = try await stack.bodyweight.entries(
            in: base...(base + day), includingDeleted: false)

        #expect(read.map(\.weight.grams) == [80_001, 80_000])
    }

    @Test("Two readings on one day are both kept — no de-duplication happens here")
    func nothingIsDeduplicated() async throws {
        let stack = try RepositoryHarness().stack
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        try await stack.bodyweight.save(bodyweightRecord(date: date, grams: 80_000))
        try await stack.bodyweight.save(bodyweightRecord(date: date, grams: 80_500))

        #expect(
            try await stack.bodyweight.entries(in: date...date, includingDeleted: false).count == 2)
    }
}
