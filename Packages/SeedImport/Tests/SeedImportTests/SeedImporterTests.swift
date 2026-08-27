import Foundation
import PowerliftingCore
import RepositoryInterface
import SeedContent
import Testing

@testable import SeedImport

// TR-0.5.1, NFR-1.7, G-2.1, FR-1.1.4. What is asserted here is mostly what an import does *not* do:
// a second run writes nothing, a rename survives, a user's own exercise is left alone, and a payload
// that does not validate costs nothing.
//
// `NFR-1.7`'s airplane-mode half is two claims, and only one of them is a test. That the shipped
// bytes load and import is `theBundledCatalogueImportsInFull` below. That nothing here can reach the
// network is `no_networking_in_seed_import`, whose entry in `.swiftlint.yml` says why it is a rule
// rather than a test and which shapes it covers.
//
// One subject, not two. The importer is a consumer of `ExerciseRepository` rather than an
// implementation of it, and `RepositoryFakes`' conformance suite is what already says the fake and
// the SwiftData repository answer alike — see this package's manifest.

@Suite("Importing the seed catalogue")
struct SeedImporterTests {

    // MARK: - The shipped catalogue

    @Test("The bundled catalogue imports in full, from the bundle")
    func theBundledCatalogueImportsInFull() async throws {
        let subject = Subject()
        let expected = try decoded(BundledCatalogue.data()).count

        let summary = try await subject.importer.importBundledCatalogue()
        let rows = try await subject.stored()

        #expect(summary.inserted == expected)
        #expect(summary.writeCount == expected)
        #expect(summary.unchanged == 0)
        #expect(rows.count == expected)
    }

    @Test("Three runs over the bundled catalogue leave one write per row")
    func threeRunsLeaveAStableRowCount() async throws {
        let subject = Subject()
        let expected = try decoded(BundledCatalogue.data()).count
        var writes: [Int] = []
        var counts: [Int] = []

        for _ in 1...3 {
            writes.append(try await subject.importer.importBundledCatalogue().writeCount)
            counts.append(try await subject.stored().count)
        }

        #expect(counts == [expected, expected, expected])
        #expect(writes == [expected, 0, 0])
    }

    @Test("A second run moves no row at all, updatedAt included")
    func aSecondRunMovesNoRow() async throws {
        // Stronger than the row count, and the claim that matters: this is what the module header's
        // no-op-save rule buys, asserted on the whole shipped catalogue rather than on one row.
        let subject = Subject()
        try await subject.importer.importBundledCatalogue()
        let before = try await subject.stored()

        try await subject.importer.importBundledCatalogue()

        #expect(try await subject.stored() == before)
        #expect(before.isEmpty == false)
    }

    @Test("A newly seeded row gets the six columns the payload has no opinion on")
    func aNewRowGetsTheColumnsThePayloadDoesNotCarry() async throws {
        let subject = Subject()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var entry = AuthoredEntry(squatID, "Back Squat")
        entry.implementCount = 2

        try await subject.importing(payload([entry]), at: now)
        let row = try #require(await subject.stored(squatID))

        #expect(row.isCustom == false)
        #expect(row.isArchived == false)
        #expect(row.notes.isEmpty)
        #expect(row.manualE1RM == nil)
        #expect(row.deletedAt == nil)
        #expect(row.createdAt == now)
        #expect(row.name == "Back Squat")
        #expect(row.implementCount == 2)
        #expect(row.movement == .squat)
        #expect(row.parentExerciseID == nil)
    }

    // MARK: - What the seed owns

    @Test("A re-import re-supplies a vocabulary the catalogue respelled", arguments: vocabularyChanges)
    func aRespelledVocabularyIsResupplied(_ change: VocabularyChange) async throws {
        let subject = Subject()
        let entry = AuthoredEntry(squatID, "Back Squat")
        #expect(change.alternative != entry.spelling(of: change.field))
        try await subject.importing(payload([entry]))

        let summary = try await subject.importing(
            payload(revision: 2, [entry.spelling(change.field, as: change.alternative)]))
        let row = try #require(await subject.stored(squatID))

        #expect(spelling(of: row, for: change.field) == change.alternative)
        #expect(summary.updated == 1)
        #expect(summary.writeCount == 1)
    }

    @Test("Every vocabulary field has an alternative spelling in the walked list")
    func everyVocabularyFieldHasAnAlternative() {
        #expect(vocabularyChanges.map(\.field) == SeedVocabularyField.allCases)
    }

    @Test("A re-import re-supplies implementCount")
    func implementCountIsResupplied() async throws {
        let subject = Subject()
        var entry = AuthoredEntry(squatID, "Dumbbell Curl")
        try await subject.importing(payload([entry]))
        #expect(try #require(await subject.stored(squatID)).implementCount == 1)

        entry.implementCount = 2
        let summary = try await subject.importing(payload(revision: 2, [entry]))

        #expect(try #require(await subject.stored(squatID)).implementCount == 2)
        #expect(summary.updated == 1)
    }

    @Test("A re-import re-supplies parentExerciseID")
    func theParentIsResupplied() async throws {
        let subject = Subject()
        let parent = AuthoredEntry(squatID, "Back Squat")
        let orphan = AuthoredEntry(frontSquatID, "Front Squat")
        try await subject.importing(payload([parent, orphan]))
        #expect(try #require(await subject.stored(frontSquatID)).parentExerciseID == nil)

        let summary = try await subject.importing(
            payload(revision: 2, [parent, child(frontSquatID, "Front Squat", of: squatID)]))

        #expect(try #require(await subject.stored(frontSquatID)).parentExerciseID == squatID)
        #expect(summary.updated == 1)
    }

    // MARK: - What the row owns

    @Test("A user-renamed built-in survives a re-import")
    func aRenameSurvives() async throws {
        let subject = Subject()
        let entry = AuthoredEntry(squatID, "Back Squat")
        try await subject.importing(payload([entry]))
        let seededRow = try #require(await subject.stored(squatID))
        try await subject.exercises.save(
            seededRow.edited(name: "Comp Squat", notes: "belt only", isArchived: true))
        let edited = try #require(await subject.stored(squatID))

        let summary = try await subject.importing(payload(revision: 2, [entry]))

        #expect(try #require(await subject.stored(squatID)) == edited)
        #expect(summary.writeCount == 0)
        #expect(summary.unchanged == 1)
    }

    @Test("Re-seeding rewrites the six seed-owned columns and touches nothing else")
    func reseedingKeepsEveryOtherColumn() async throws {
        // The round trip the eight `stamped` conformances are tested with, applied to the merge: an
        // entry whose seed-owned columns already agree must leave the row identical, so a dropped
        // user column cannot survive. `aRespelledVocabularyIsResupplied` is the opposite check —
        // together they catch a merge that forgets a column and one that ignores its entry.
        let subject = Subject()
        let entry = AuthoredEntry(squatID, "Back Squat")
        try await subject.importing(payload([entry]))
        let edited = try #require(await subject.stored(squatID))
            .edited(
                name: "Comp Squat",
                notes: "belt only",
                isArchived: true,
                isCustom: true,
                manualE1RM: Weight(grams: 182_500))

        let decodedEntry = try #require(decoded(payload([entry])).first)

        #expect(edited.reseeded(from: decodedEntry) == edited)
    }

    @Test("An exercise the user authored is never written")
    func aUserAuthoredRowIsNeverWritten() async throws {
        let subject = Subject()
        // One custom row wearing a catalogue id, one the catalogue never mentions. Neither may be
        // corrected, and the second may not be archived either: an exercise the user authored was
        // never in the catalogue, so its absence from one says nothing.
        try await subject.exercises.save(userAuthored(squatID, "My Squat"))
        try await subject.exercises.save(userAuthored(customID, "My Machine Thing"))
        let before = try await subject.stored()

        let summary = try await subject.importing(
            payload([AuthoredEntry(squatID, "Back Squat"), AuthoredEntry(benchID, "Bench")]))

        // Both sides anchored with `#require`: two optionals compared directly are satisfied by
        // `nil == nil`, so an import that lost the rows entirely would pass.
        #expect(try #require(await subject.stored(squatID)) == (try #require(before.first { $0.id == squatID })))
        #expect(try #require(await subject.stored(customID)) == (try #require(before.first { $0.id == customID })))
        #expect(summary == SeedImportSummary(inserted: 1, updated: 0, archived: 0, unchanged: 1))
    }

    @Test("An id carried by two rows is resolved by the repository, not by the snapshot")
    func aDuplicatedIDDefersToTheRepository() async throws {
        // The merge reads the whole store once and answers from that snapshot, which is only safe
        // while an id names one row. `G-2.5` forbids the constraint that would guarantee it, so the
        // pair has to fall back to `exercise(id:)` — the layer that owns the tiebreak.
        let subject = Subject()
        let entry = AuthoredEntry(squatID, "Back Squat")
        try await subject.importing(payload([entry]))
        let row = try #require(await subject.stored(squatID))
        // The twin disagrees in a seed-owned column, so answering from the snapshot instead of the
        // repository would re-supply that column and count an update.
        let twin = row.edited(movement: .deadlift)
        #expect(twin != row)
        let doubled = SeedImporter(
            exercises: DuplicateIDRepository(base: subject.exercises, twin: twin))

        let summary = try await doubled.importCatalogue(
            from: payload(revision: 2, [entry]), minimumExercises: 1)

        #expect(summary == SeedImportSummary(inserted: 0, updated: 0, archived: 0, unchanged: 1))
        #expect(try #require(await subject.stored(squatID)) == row)
    }

    // MARK: - Added and removed built-ins

    @Test("A new built-in is added on re-import")
    func aNewBuiltInIsAdded() async throws {
        let subject = Subject()
        let squat = AuthoredEntry(squatID, "Back Squat")
        try await subject.importing(payload([squat]))

        let summary = try await subject.importing(
            payload(revision: 2, [squat, AuthoredEntry(benchID, "Bench Press")]))

        #expect(try await subject.stored().count == 2)
        #expect(summary == SeedImportSummary(inserted: 1, updated: 0, archived: 0, unchanged: 1))
    }

    @Test("A removed built-in is archived rather than deleted")
    func aRemovedBuiltInIsArchived() async throws {
        let subject = Subject()
        let squat = AuthoredEntry(squatID, "Back Squat")
        try await subject.importing(
            payload([squat, AuthoredEntry(benchID, "Bench Press")]))

        let summary = try await subject.importing(payload(revision: 2, [squat]))
        let removed = try #require(await subject.stored(benchID))

        #expect(removed.isArchived)
        #expect(removed.deletedAt == nil)
        #expect(removed.name == "Bench Press")
        #expect(try await subject.stored().count == 2)
        #expect(summary == SeedImportSummary(inserted: 0, updated: 0, archived: 1, unchanged: 1))
        #expect(summary.writeCount == 1)
    }

    @Test("Archiving a removed built-in happens once")
    func archivingIsIdempotent() async throws {
        let subject = Subject()
        let squat = AuthoredEntry(squatID, "Back Squat")
        try await subject.importing(
            payload([squat, AuthoredEntry(benchID, "Bench Press")]))
        try await subject.importing(payload(revision: 2, [squat]))
        let archived = try await subject.stored()

        let summary = try await subject.importing(payload(revision: 3, [squat]))

        #expect(try await subject.stored() == archived)
        #expect(summary.writeCount == 0)
    }

    @Test("A built-in that returns to the catalogue is not un-archived")
    func aReturningBuiltInStaysArchived() async throws {
        // Archiving is one-way, for the reason `Exercise.archived()` gives.
        let subject = Subject()
        let squat = AuthoredEntry(squatID, "Back Squat")
        let bench = AuthoredEntry(benchID, "Bench Press")
        try await subject.importing(payload([squat, bench]))
        try await subject.importing(payload(revision: 2, [squat]))

        let summary = try await subject.importing(
            payload(revision: 3, [squat, bench]))

        #expect(try #require(await subject.stored(benchID)).isArchived)
        #expect(summary.writeCount == 0)
    }

    // MARK: - Ordering, end to end

    @Test("A catalogue listing a variation above its parent imports")
    func aVariationAboveItsParentImports() async throws {
        // `save` refuses a `parentExerciseID` naming a row that does not exist, and
        // `SeedCatalogue.exercises` is in authoring order — so an importer that walked the payload
        // as written would throw `danglingReference` on the first variation.
        let subject = Subject()

        let summary = try await subject.importing(
            payload([
                child(frontSquatID, "Front Squat", of: squatID),
                AuthoredEntry(squatID, "Back Squat"),
            ]))

        #expect(try #require(await subject.stored(frontSquatID)).parentExerciseID == squatID)
        #expect(summary.inserted == 2)
    }

    // MARK: - Refusals

    @Test("A payload that does not validate is refused, and writes nothing")
    func anInvalidPayloadWritesNothing() async throws {
        let subject = Subject()
        var broken = AuthoredEntry(benchID, "Bench Press")
        broken.movement = "sled"
        let data = payload([AuthoredEntry(squatID, "Back Squat"), broken])

        let error = await #expect(throws: SeedImportError.self) {
            try await subject.importing(data)
        }

        #expect(
            error
                == .invalidPayload([
                    .unknownVocabulary(exercise: benchID, field: .movement, value: "sled")
                ]))
        // The valid entry precedes the broken one, so a validator running per entry would have
        // written it before finding the fault.
        #expect(try await subject.stored().isEmpty)
    }

    @Test("A payload with too few entries is refused")
    func tooFewEntriesIsRefused() async throws {
        let subject = Subject()
        let data = payload([AuthoredEntry(squatID, "Back Squat"), AuthoredEntry(benchID, "Bench")])

        let error = await #expect(throws: SeedImportError.self) {
            try await subject.importing(data, minimum: 5)
        }

        #expect(error == .invalidPayload([.tooFewExercises(count: 2, minimum: 5)]))
        #expect(try await subject.stored().isEmpty)
    }

    @Test("A refused re-import leaves the rows an earlier import wrote")
    func aRefusedReimportChangesNothing() async throws {
        let subject = Subject()
        try await subject.importing(payload([AuthoredEntry(squatID, "Squat")]))
        let before = try await subject.stored()
        var broken = AuthoredEntry(squatID, "Squat")
        broken.barType = "none"

        await #expect(throws: SeedImportError.self) {
            try await subject.importing(payload(revision: 2, [broken]))
        }

        #expect(try await subject.stored() == before)
    }
}
