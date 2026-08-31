import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData
import Testing

@testable import Persistence

@Suite("Entity ↔ record round trip")
struct RecordMappingRoundTripTests {
    // T-0.41's done-when, one test per entity. Each writes a row, reads it back out of the store,
    // maps it to a record and applies that record to a *different* row whose every mapped column
    // holds a different value — so a mapping that dropped a column, or wrote nothing at all, is an
    // inequality rather than a coincidence.
    //
    // Two of the nine are the ones the done-when was in doubt over, and both are here for that
    // reason rather than for symmetry: the exercise carries four vocabulary columns, and the
    // profile's inventory is malformed on purpose.

    @Test("An exercise round-trips through a record")
    func exerciseRoundTrips() throws {
        let context = try makeTrainingContext()
        let id = UUID()
        try assertRoundTrips(
            source: mappingSourceExercise(id: id),
            target: mappingTargetExercise(id: id),
            record: \.record,
            update: { $0.update(from: $1) },
            in: context)
    }

    @Test("A session round-trips through a record")
    func sessionRoundTrips() throws {
        let context = try makeTrainingContext()
        let id = UUID()
        try assertRoundTrips(
            source: mappingSourceSession(id: id),
            target: mappingTargetSession(id: id),
            record: \.record,
            update: { $0.update(from: $1) },
            in: context)
    }

    @Test("An exercise entry round-trips through a record")
    func entryRoundTrips() throws {
        let context = try makeTrainingContext()
        let id = UUID()
        try assertRoundTrips(
            source: mappingSourceEntry(id: id),
            target: mappingTargetEntry(id: id),
            record: \.record,
            update: { $0.update(from: $1) },
            in: context)
    }

    @Test("A set round-trips through a record, unrecognised modifier included")
    func setRoundTrips() throws {
        let context = try makeTrainingContext()
        let id = UUID()
        try assertRoundTrips(
            source: mappingSourceSet(id: id),
            target: mappingTargetSet(id: id),
            record: \.record,
            update: { $0.update(from: $1) },
            in: context)
    }

    @Test("A bodyweight reading round-trips through a record")
    func bodyweightRoundTrips() throws {
        let context = try makeSupportingContext()
        let id = UUID()
        try assertRoundTrips(
            source: mappingSourceBodyweight(id: id),
            target: mappingTargetBodyweight(id: id),
            record: \.record,
            update: { $0.update(from: $1) },
            in: context)
    }

    @Test("A training-max configuration round-trips through a record")
    func trainingMaxRoundTrips() throws {
        let context = try makeSupportingContext()
        let id = UUID()
        try assertRoundTrips(
            source: mappingSourceTrainingMax(id: id),
            target: mappingTargetTrainingMax(id: id),
            record: \.record,
            update: { $0.update(from: $1) },
            in: context)
    }

    // The half of the done-when that needed the schema to change. The fixture's inventory lists
    // 25 kg twice, which `PlateInventory` refuses — so before `replaceInventory(plateGrams:
    // platePairCounts:)` existed this row could be read into a record and not written back out of
    // one, and a restore would have lost the profile and its name along with its plates.
    @Test("A profile round-trips through a record even when its inventory is malformed")
    func profileRoundTrips() throws {
        let context = try makeSupportingContext()
        let id = UUID()
        try assertRoundTrips(
            source: mappingSourceProfile(id: id),
            target: mappingTargetProfile(id: id),
            record: \.record,
            update: { $0.update(from: $1) },
            in: context)
    }

    @Test("Settings round-trip through a record")
    func settingsRoundTrip() throws {
        let context = try makeSupportingContext()
        let id = UUID()
        try assertRoundTrips(
            source: mappingSourceSettings(id: id),
            target: mappingTargetSettings(id: id),
            record: \.record,
            update: { $0.update(from: $1) },
            in: context)
    }

    @Test("A cached personal record round-trips through a record")
    func cacheRoundTrips() throws {
        let context = try makeSupportingContext()
        let id = UUID()
        try assertRoundTrips(
            source: mappingSourceCache(id: id),
            target: mappingTargetCache(id: id),
            record: \.record,
            update: { $0.update(from: $1) },
            in: context)
    }

    // The other direction of the same claim, for all nine: `init(record:)` reproduces every mapped
    // column on a brand-new row. Anchored on the whole record rather than field by field, which is
    // what `deletedAt: nil` buys — a live row is the one case where the insert direction is lossless
    // in full, and the deleted one has its own assertion in the audit suite.
    @Test("A new row built from a live record reads back as that record")
    func insertingARecordReproducesIt() {
        assertInsertReproduces(
            mappingSourceExercise(id: UUID()),
            insert: ExerciseEntity.init(record:),
            read: \.record)
        assertInsertReproduces(
            mappingSourceSession(id: UUID()),
            insert: WorkoutSessionEntity.init(record:),
            read: \.record)
        assertInsertReproduces(
            mappingSourceEntry(id: UUID()),
            insert: ExerciseEntryEntity.init(record:),
            read: \.record)
        assertInsertReproduces(
            mappingSourceSet(id: UUID()),
            insert: SetEntryEntity.init(record:),
            read: \.record)
        assertInsertReproduces(
            mappingSourceBodyweight(id: UUID()),
            insert: BodyweightEntryEntity.init(record:),
            read: \.record)
        assertInsertReproduces(
            mappingSourceTrainingMax(id: UUID()),
            insert: TrainingMaxConfigEntity.init(record:),
            read: \.record)
        assertInsertReproduces(
            mappingSourceProfile(id: UUID()),
            insert: EquipmentProfileEntity.init(record:),
            read: \.record)
        assertInsertReproduces(
            mappingSourceSettings(id: UUID()),
            insert: UserSettingsEntity.init(record:),
            read: \.record)
        assertInsertReproduces(
            mappingSourceCache(id: UUID()),
            insert: PersonalRecordCacheEntity.init(record:),
            read: \.record)
    }
}

@Suite("The audit columns are not the mapping's")
struct RecordMappingAuditColumnTests {
    // Rule 7 of the RepositoryInterface header, made structural. `updatedAt` belongs to
    // `saveStamped(at:)` and `deletedAt` to `markDeleted(at:)`, so `update(from:)` writing either
    // would let a caller relabel history by saving a record it edited.
    //
    // Every expectation is against a literal rather than against the source record's field, which
    // would compare a copy with itself.
    @Test("update(from:) leaves id, createdAt, updatedAt and deletedAt alone")
    func updateIgnoresTheAuditColumns() throws {
        let target = mappingTargetExercise(id: UUID())
        let targetID = target.id
        target.createdAt = Date(timeIntervalSince1970: 1)
        target.updatedAt = Date(timeIntervalSince1970: 2)
        target.deletedAt = nil

        target.update(from: mappingSourceExercise(id: UUID()).record)

        #expect(target.id == targetID)
        #expect(target.createdAt == Date(timeIntervalSince1970: 1))
        #expect(target.updatedAt == Date(timeIntervalSince1970: 2))
        #expect(target.deletedAt == nil)
    }

    // `init(record:)` honours `createdAt` — an import or a restore keeps the history it arrived
    // with — and does not honour `deletedAt`, which is the one thing this layer cannot express and
    // FR-1.11.3's restore will need its own writer for.
    @Test("A new row keeps the record's createdAt and arrives live")
    func insertHonoursCreatedAtAndNotDeletedAt() {
        let source = mappingSourceSet(id: UUID())
        source.deletedAt = Date(timeIntervalSince1970: 9)

        let inserted = SetEntryEntity(record: source.record)

        #expect(inserted.createdAt == mappingCreatedAt)
        #expect(inserted.deletedAt == nil)
    }

    // The same shape as `userID` below, and the same reason: "exactly one default" is a cross-row
    // invariant that a record — a mirror of one row — cannot carry, so the mapping declines to write
    // it and `EquipmentRepository.save(_:)` keeps its "not written by this, whatever the record
    // carries" promise by doing nothing. `G-2.5` forbids the constraint that would notice two rows
    // claiming it, so nothing else would catch a save that honoured the flag.
    @Test("Updating a profile leaves the default flag alone")
    func profileUpdateLeavesTheDefaultFlagAlone() {
        let target = mappingTargetProfile(id: UUID())
        target.isDefault = false

        target.update(from: mappingSourceProfile(id: UUID()).record)

        #expect(target.isDefault == false)
    }

    // …and the insert direction does write it, because a new row has nothing to keep and a restore
    // has to reinstate what the backup carried.
    @Test("A new profile built from a record carries its default flag")
    func insertingAProfileCarriesTheDefaultFlag() {
        let source = mappingSourceProfile(id: UUID())

        #expect(EquipmentProfileEntity(record: source.record).isDefault == true)
    }

    // TR-1.10: `userID` is minted once and this layer never writes it. A save carrying a different
    // one is the repository's to refuse, which it cannot do if the mapping has already overwritten
    // the stored value.
    @Test("Updating settings leaves the anonymous identity alone")
    func settingsUpdateLeavesTheIdentityAlone() {
        let stored = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc") ?? UUID()
        let incoming = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd") ?? UUID()
        let target = mappingTargetSettings(id: UUID(), userID: stored)

        target.update(from: mappingSourceSettings(id: UUID(), userID: incoming).record)

        #expect(target.userID == stored)
    }
}

@Suite("Unreadable vocabulary spellings")
struct RecordVocabularyMappingTests {
    // Rule 4: an unreadable field costs that field and never the row. Eleven columns, and each is
    // asserted twice — the resolved value, and one neighbouring column that must have survived.
    // Asserting only the fallback would pass for a mapping that returned a blank record.

    @Test("An unreadable exercise vocabulary resolves without costing the row")
    func exerciseVocabularyResolves() {
        let entity = mappingSourceExercise(id: UUID())
        entity.movementRawValue = "kettlebellSwing"
        entity.equipmentRawValue = "sled"
        entity.lateralityRawValue = "contralateral"
        entity.barTypeRawValue = "axle"

        let record = entity.record

        #expect(record.movement == .other)
        #expect(record.equipment == .other)
        #expect(record.laterality == .bilateral)
        #expect(record.barType == .other)
        #expect(record.name == "Low-bar back squat")
        #expect(record.implementCount == 2)
    }

    @Test("An unreadable bodyweight source resolves without costing the reading")
    func bodyweightSourceResolves() {
        let entity = mappingSourceBodyweight(id: UUID())
        entity.sourceRawValue = "smartScale"

        let record = entity.record

        #expect(record.source == .manual)
        #expect(record.weight == Weight(grams: 82_400))
    }

    @Test("An unreadable training-max source and strategy resolve without costing the row")
    func trainingMaxVocabularyResolves() {
        let entity = mappingSourceTrainingMax(id: UUID())
        entity.sourceRawValue = "percentOfVelocityLoss"
        entity.roundingStrategyRawValue = "bankers"

        let record = entity.record

        #expect(record.source == .manual)
        #expect(record.roundingStrategy == .nearest)
        #expect(record.percentage == 0.85)
    }

    @Test("An unreadable preference resolves without costing the other three")
    func settingsVocabularyResolves() {
        let entity = mappingSourceSettings(id: UUID())
        entity.displayUnitRawValue = "stones"
        entity.e1RMFormulaRawValue = "mayhew"
        entity.themeRawValue = "sepia"
        entity.defaultRoundingStrategyRawValue = "bankers"

        let record = entity.record

        #expect(record.displayUnit == .kilograms)
        #expect(record.e1RMFormula == .epley)
        #expect(record.theme == .system)
        #expect(record.defaultRoundingStrategy == .nearest)
        #expect(record.userID == mappingUserID)
    }

    // The half that makes the round trip true rather than nearly true, and the one a blind
    // `entity.movementRawValue = record.movement.rawValue` would fail. `G-1.6` forbids modifying
    // logged data, and relabelling a column as "other" while the user edits the *name* is exactly
    // that — the spelling is still correct on the device that wrote it.
    //
    // All three marker vocabularies, because the flag that permits this is per-vocabulary and
    // `Movement` alone would not show the other two carrying it.
    @Test("Writing back an unmappable spelling does not rewrite it")
    func unmappableSpellingSurvivesAWriteBack() {
        let entity = mappingSourceExercise(id: UUID())
        entity.movementRawValue = "kettlebellSwing"
        entity.equipmentRawValue = "sled"
        entity.barTypeRawValue = "axle"

        var record = entity.record
        #expect(record.movement == .other)

        entity.update(from: record)
        #expect(entity.movementRawValue == "kettlebellSwing")
        #expect(entity.equipmentRawValue == "sled")
        #expect(entity.barTypeRawValue == "axle")

        // …and a caller that genuinely changes the column still wins, which is what makes this
        // preservation rather than a column nothing can write.
        record = Exercise(
            id: record.id,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            deletedAt: record.deletedAt,
            name: record.name,
            ukrainianName: nil,
            movement: .deadlift,
            parentExerciseID: record.parentExerciseID,
            equipment: record.equipment,
            laterality: record.laterality,
            barType: record.barType,
            implementCount: record.implementCount,
            isCustom: record.isCustom,
            isArchived: record.isArchived,
            notes: record.notes,
            manualE1RM: nil)
        entity.update(from: record)
        #expect(entity.movementRawValue == "deadlift")
    }

    // The other half of the rule, and the half a first draft got wrong. `Laterality` has no unknown
    // case, so its fallback is a real answer — and preserving there would mean a user who picks
    // Bilateral cannot make it stick, because the record they save agrees with what the column
    // already reads as. The record wins instead. The cost is that a spelling a newer version wrote
    // is overwritten, but only on a row this user saved while being shown "bilateral".
    @Test("An unmappable laterality is overwritten on a write back")
    func unmappableLateralityIsOverwritten() {
        let entity = mappingSourceExercise(id: UUID())
        entity.lateralityRawValue = "contralateral"

        entity.update(from: entity.record)

        #expect(entity.lateralityRawValue == "bilateral")
    }

    // The bug that rule exists to prevent, on the columns where it would actually be met: a
    // preference whose stored spelling this version cannot read must still be settable *to* the
    // value it currently reads as. Preserving here would make each of these permanently unreachable
    // — the record agrees with the store, so nothing is written, on this save and on every one
    // after it.
    //
    // All four asserted rather than one: they are four separate `RecordVocabulary` constants, and
    // the flag that decides this is per-vocabulary.
    @Test("A preference can be set to the value a foreign spelling resolves to")
    func substantiveFallbacksAreSettable() {
        let entity = mappingSourceSettings(id: UUID())
        entity.displayUnitRawValue = "stones"
        entity.e1RMFormulaRawValue = "mayhew"
        entity.themeRawValue = "sepia"
        entity.defaultRoundingStrategyRawValue = "bankers"

        // The record reads as the four fallbacks, and saving it back is the user accepting them.
        entity.update(from: entity.record)

        #expect(entity.displayUnitRawValue == "kilograms")
        #expect(entity.e1RMFormulaRawValue == "epley")
        #expect(entity.themeRawValue == "system")
        #expect(entity.defaultRoundingStrategyRawValue == "nearest")
    }

    // And the same for the two storage vocabularies on the other entities, so the flag is exercised
    // on every constant that carries it rather than on the four that happen to sit together.
    @Test("A source column can be set to the value a foreign spelling resolves to")
    func substantiveSourceFallbacksAreSettable() {
        let reading = mappingSourceBodyweight(id: UUID())
        reading.sourceRawValue = "smartScale"
        reading.update(from: reading.record)

        let configuration = mappingSourceTrainingMax(id: UUID())
        configuration.sourceRawValue = "percentOfVelocityLoss"
        configuration.roundingStrategyRawValue = "bankers"
        configuration.update(from: configuration.record)

        #expect(reading.sourceRawValue == "manual")
        #expect(configuration.sourceRawValue == "manual")
        #expect(configuration.roundingStrategyRawValue == "nearest")
    }

    // The duplication T-0.40 blessed, kept honest. `SchemaDefaults` holds what an *absent* column
    // contains and `RecordVocabulary` what an *unreadable* value becomes; they coincide by argument
    // rather than by identity, so this asserts the coincidence rather than sharing a constant. A
    // deliberate divergence edits this test, which is the point of it existing.
    @Test("Every schema default and its mapping fallback agree")
    func schemaDefaultsAndFallbacksAgree() {
        #expect(SchemaDefaults.movement == RecordVocabulary.movement.value.rawValue)
        #expect(SchemaDefaults.equipment == RecordVocabulary.equipment.value.rawValue)
        #expect(SchemaDefaults.laterality == RecordVocabulary.laterality.value.rawValue)
        #expect(SchemaDefaults.barType == RecordVocabulary.barType.value.rawValue)
        #expect(SchemaDefaults.bodyweightSource == RecordVocabulary.bodyweightSource.value.rawValue)
        #expect(SchemaDefaults.trainingMaxSource == RecordVocabulary.trainingMaxSource.value.rawValue)
        #expect(SchemaDefaults.roundingStrategy == RecordVocabulary.roundingStrategy.value.rawValue)
        #expect(SchemaDefaults.displayUnit == RecordVocabulary.displayUnit.value.rawValue)
        #expect(SchemaDefaults.e1RMFormula == RecordVocabulary.e1RMFormula.value.rawValue)
        #expect(SchemaDefaults.theme == RecordVocabulary.theme.value.rawValue)
    }
}

@Suite("A malformed inventory reaches the store and comes back")
struct EquipmentInventoryMappingTests {
    // What the raw writer is for, stated as the two things it must not do. Neither is checked by
    // the round-trip test above, which would pass for a writer that sorted or deduplicated as long
    // as it did so on both sides.
    //
    // The fixture is deliberately unsorted as well as repeating, and that came from a probe: with a
    // heaviest-first fixture, a writer that sorted survived every test here, because sorting an
    // already-sorted list is the identity.
    @Test("The raw writer neither sorts nor deduplicates")
    func rawWriterPreservesTheListsVerbatim() throws {
        let context = try makeSupportingContext()
        let entity = mappingSourceProfile(id: UUID())
        context.insert(entity)
        try context.save()

        #expect(entity.plateGrams == [15_000, 25_000, 25_000])
        #expect(entity.platePairCounts == [3, 2, 1])
    }

    // The pairing a validating writer could not express at all: two lists of different lengths is
    // what a synced profile looks like when one CloudKit field arrived and the other did not.
    @Test("Lists of different lengths survive a round trip")
    func mismatchedListsSurvive() {
        let source = mappingSourceProfile(id: UUID())
        source.replaceInventory(plateGrams: [20_000, 25_000], platePairCounts: [2])
        let target = mappingTargetProfile(id: source.id)

        target.update(from: source.record)

        #expect(target.plateGrams == [20_000, 25_000])
        #expect(target.platePairCounts == [2])
    }

    // And the writer that authoring call sites use still normalises, so the two are not the same
    // method wearing two names.
    @Test("The validating writer still normalises to heaviest first")
    func validatingWriterStillNormalises() throws {
        let entity = mappingTargetProfile(id: UUID())
        let inventory = try makeInventory([(grams: 15_000, pairs: 3), (grams: 25_000, pairs: 2)])

        entity.replaceInventory(with: inventory)

        #expect(entity.plateGrams == [25_000, 15_000])
        #expect(entity.platePairCounts == [2, 3])
    }
}
