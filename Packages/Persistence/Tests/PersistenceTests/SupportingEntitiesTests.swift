import Foundation
import PowerliftingCore
import SwiftData
import Testing

@testable import Persistence

@Suite("Supporting entities")
struct SupportingEntitiesTests {
    @Test("BodyweightEntryEntity honours the conventions against a real store")
    func bodyweightHonoursConventions() throws {
        let context = try makeSupportingContext()
        try assertStoredEntityConventions(
            { BodyweightEntryEntity(date: .distantPast, weightGrams: 82_000, source: .manual) },
            in: context
        )
    }

    @Test("TrainingMaxConfigEntity honours the conventions against a real store")
    func trainingMaxConfigHonoursConventions() throws {
        let context = try makeSupportingContext()
        try assertStoredEntityConventions(
            { makeTrainingMaxConfig(source: .percentOfE1RM) },
            in: context
        )
    }

    @Test("EquipmentProfileEntity honours the conventions against a real store")
    func equipmentProfileHonoursConventions() throws {
        let context = try makeSupportingContext()
        let inventory = try makeInventory([(20_000, 2)])
        try assertStoredEntityConventions(
            {
                EquipmentProfileEntity(
                    name: "Home",
                    barWeightGrams: 20_000,
                    collarWeightGrams: 2_500,
                    inventory: inventory
                )
            },
            in: context
        )
    }

    // Names the initialiser directly rather than going through `makeSettings`, so the signature
    // TR-1.10 rests on — a userID with no default argument — is exercised as written.
    @Test("UserSettingsEntity honours the conventions against a real store")
    func settingsHonourConventions() throws {
        let context = try makeSupportingContext()
        try assertStoredEntityConventions(
            {
                UserSettingsEntity(
                    userID: UUID(),
                    displayUnit: .kilograms,
                    e1RMFormula: .epley,
                    theme: .system,
                    defaultRoundingIncrementGrams: 2_500,
                    defaultRoundingStrategy: .nearest
                )
            },
            in: context
        )
    }

    @Test("PersonalRecordCacheEntity honours the conventions against a real store")
    func recordCacheHonoursConventions() throws {
        let context = try makeSupportingContext()
        try assertStoredEntityConventions(
            { makeCachedRecord(exerciseID: UUID(), repCount: 5, weightGrams: 150_000) },
            in: context
        )
    }

    @Test("Every bodyweight field survives a save and a re-read")
    func bodyweightRoundTrips() throws {
        let context = try makeSupportingContext()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(BodyweightEntryEntity(date: day, weightGrams: 82_350, source: .healthKit))
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<BodyweightEntryEntity>.notDeleted()).first
        )

        #expect(stored.date == day)
        #expect(stored.weightGrams == 82_350)
        #expect(stored.sourceRawValue == "healthKit")
    }

    // TR-0.2.2's rule one layer out: reordering a case must not rewrite history, so the persisted
    // spellings of the three vocabularies this module declares are pinned to literals.
    @Test("The storage vocabularies persist as their spellings, not as ordinals")
    func storageVocabularySpellings() {
        #expect(BodyweightSource.allCases.map(\.rawValue) == ["manual", "healthKit"])
        #expect(ThemePreference.allCases.map(\.rawValue) == ["system", "light", "dark"])
        #expect(
            TrainingMaxSourceKind.allCases.map(\.rawValue) == [
                "percentOfE1RM", "percentOfRepMax", "manual",
            ]
        )
    }

    // G-2.4: saveStamped(at:) walks `any StoredEntity`, so it reaches five types that did not exist
    // when it was written — including the one conforming through CachedDerivedEntity rather than
    // directly. Asserted per type rather than in aggregate: a stamp missing from one of five is
    // exactly the failure a count would hide.
    @Test("One stamped save reaches all five supporting entities")
    func stampingReachesEverySupportingEntity() throws {
        let context = try makeSupportingContext()
        let stamp = Date(timeIntervalSince1970: 1_700_003_600)
        let userID = try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000FF"))
        let bodyweight = BodyweightEntryEntity(date: .distantPast, weightGrams: 82_000, source: .manual)
        let config = makeTrainingMaxConfig(source: .percentOfE1RM)
        let profile = EquipmentProfileEntity(
            name: "Home",
            barWeightGrams: 20_000,
            collarWeightGrams: 2_500,
            inventory: try makeInventory([(20_000, 2)])
        )
        let settings = makeSettings(userID: userID)
        let record = makeCachedRecord(exerciseID: UUID(), repCount: 1, weightGrams: 200_000)

        for model in [bodyweight, config, profile, settings, record] as [any StoredEntity] {
            context.insert(model)
        }
        try context.saveStamped(at: stamp)

        #expect(bodyweight.updatedAt == stamp)
        #expect(config.updatedAt == stamp)
        #expect(profile.updatedAt == stamp)
        #expect(settings.updatedAt == stamp)
        #expect(record.updatedAt == stamp)
    }

    // G-1.3 reaches the supporting entities too: a soft-deleted profile stays in the store and out
    // of every default read, and takes none of its siblings with it.
    @Test("Soft-deleting one equipment profile leaves the others alone")
    func softDeletingOneProfile() throws {
        let context = try makeSupportingContext()
        let inventory = try makeInventory([(20_000, 3), (10_000, 2)])
        let profiles = ["Home", "Commercial", "Meet"].map { name in
            EquipmentProfileEntity(
                name: name,
                barWeightGrams: 20_000,
                collarWeightGrams: 2_500,
                inventory: inventory
            )
        }
        for model in profiles { context.insert(model) }
        try context.saveStamped()

        profiles[1].markDeleted()
        try context.saveStamped()

        let live = try context.fetch(
            FetchDescriptor<EquipmentProfileEntity>.notDeleted(sortBy: [SortDescriptor(\.name)])
        )
        let all = try context.fetch(FetchDescriptor<EquipmentProfileEntity>.includingDeleted())

        #expect(live.map(\.name) == ["Home", "Meet"])
        #expect(all.count == 3)
    }
}
