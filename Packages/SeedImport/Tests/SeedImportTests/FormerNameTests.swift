import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import SeedContent
import Testing

@testable import SeedImport

// FR-18.2.1, FR-1.1.4, TR-18.1, DOD-18.5. A catalogue entry lists the names it used to carry, and
// the importer replaces a stored name only when it still equals one of them.
//
// **The five claims are walked over the two languages rather than written twice.** English and
// Ukrainian take the same rule, and a rule written out per language is a rule that passes while the
// other half goes unchecked — the same argument `SeedCatalogueValidator` gives for walking
// `SeedVocabularyField.allCases`. What differs between the two is which column the entry authors and
// which column the store holds, so that is exactly what `NameLanguage` carries and nothing else.

/// One of the two names an entry may correct, so the same five claims are made about both.
struct NameLanguage: Sendable, CustomTestStringConvertible {
    let testDescription: String

    /// `entry` carrying `current` as this language's name, having formerly carried `former`.
    let authored: @Sendable (AuthoredEntry, String, [String]) -> AuthoredEntry

    /// What the stored row holds for this language.
    let stored: @Sendable (Exercise) -> String?

    /// `row` with this language's name set to `value` — a lifter's own edit, or a fixture's setup.
    let naming: @Sendable (Exercise, String) -> Exercise

    static let english = NameLanguage(
        testDescription: "English",
        authored: { entry, current, former in entry.renamed(to: current, formerly: former) },
        stored: { $0.name },
        naming: { row, value in row.edited(name: value) })

    static let ukrainian = NameLanguage(
        testDescription: "Ukrainian",
        authored: { entry, current, former in entry.retranslated(to: current, formerly: former) },
        stored: { $0.ukrainianName },
        naming: { row, value in row.edited(ukrainianName: value) })

    static let both: [NameLanguage] = [.english, .ukrainian]
}

@Suite("Correcting a catalogue name")
struct FormerNameTests {
    private let id = UUID()
    private let old = "Rear Delt Machine Swings"
    private let new = "Machine Rear Delt Fly"

    /// The revision before the correction: one entry carrying `old`, listing nothing.
    private func beforeTheCorrection(_ language: NameLanguage) -> Data {
        payload([language.authored(AuthoredEntry(id, "Lift"), old, [])])
    }

    /// The revision that corrects it: the same entry carrying `new` and listing `old`.
    private func afterTheCorrection(_ language: NameLanguage) -> Data {
        payload(revision: 2, [language.authored(AuthoredEntry(id, "Lift"), new, [old])])
    }

    // MARK: - The five claims, in both languages

    @Test("A name nobody touched is replaced by the correction", arguments: NameLanguage.both)
    func anUntouchedNameIsCorrected(_ language: NameLanguage) async throws {
        let subject = Subject()
        try await subject.importing(beforeTheCorrection(language))

        try await subject.importing(afterTheCorrection(language))

        let row = try #require(try await subject.stored(id))
        #expect(language.stored(row) == new)
    }

    @Test("A name the lifter typed survives the correction", arguments: NameLanguage.both)
    func aLiftersOwnNameSurvives(_ language: NameLanguage) async throws {
        let subject = Subject()
        try await subject.importing(beforeTheCorrection(language))
        let seeded = try #require(try await subject.stored(id))
        try await subject.exercises.save(language.naming(seeded, "What I call it"))

        try await subject.importing(afterTheCorrection(language))

        let row = try #require(try await subject.stored(id))
        #expect(language.stored(row) == "What I call it")
    }

    @Test("A stored name already at the current one is not rewritten", arguments: NameLanguage.both)
    func aNameAlreadyCurrentIsNotRewritten(_ language: NameLanguage) async throws {
        // The row holds `new` and the entry still lists `old`, which is the state every install
        // that arrived after the correction is in — and the one where a rule that replaced
        // unconditionally would restamp `updatedAt` on every launch forever (`G-2.4`).
        let counter = CountingExerciseRepository(wrapping: InMemoryRepositoryStack().exercises)
        let subject = Subject(over: counter)
        try await subject.importing(afterTheCorrection(language))
        let before = try await subject.stored()
        let writes = await counter.saves

        try await subject.importing(afterTheCorrection(language))

        #expect(try await subject.stored() == before)
        #expect(await counter.saves == writes)
    }

    @Test("An exercise the lifter authored is never corrected", arguments: NameLanguage.both)
    func aCustomExerciseIsNeverCorrected(_ language: NameLanguage) async throws {
        // `isCustom` is asked before the correction is, and stays that way: a row the lifter wrote
        // is not the catalogue's to fix even when it happens to carry a name the catalogue retired.
        let subject = Subject()
        try await subject.exercises.save(language.naming(userAuthored(id, "Lift"), old))

        let summary = try await subject.importing(afterTheCorrection(language))

        let row = try #require(try await subject.stored(id))
        #expect(language.stored(row) == old)
        #expect(summary.writeCount == 0)
    }

    @Test("A second import of the same revision writes nothing", arguments: NameLanguage.both)
    func aSecondImportWritesNothing(_ language: NameLanguage) async throws {
        // Counted on `save` rather than read off the summary: the summary is arithmetic over the
        // importer's own branches, so a rule that stopped saving and kept counting would agree with
        // itself. This is what the `merged != existing` guard buys, asserted after the change.
        let counter = CountingExerciseRepository(wrapping: InMemoryRepositoryStack().exercises)
        let subject = Subject(over: counter)
        try await subject.importing(beforeTheCorrection(language))
        try await subject.importing(afterTheCorrection(language))
        let afterTheRename = await counter.saves

        try await subject.importing(afterTheCorrection(language))

        #expect(afterTheRename == 2)
        #expect(await counter.saves == afterTheRename)
    }

    // MARK: - What equality means

    @Test("A name retyped in different case is a name the lifter touched", arguments: NameLanguage.both)
    func caseIsNotFolded(_ language: NameLanguage) async throws {
        let subject = Subject()
        try await subject.importing(beforeTheCorrection(language))
        let seeded = try #require(try await subject.stored(id))
        try await subject.exercises.save(language.naming(seeded, old.uppercased()))

        try await subject.importing(afterTheCorrection(language))

        let row = try #require(try await subject.stored(id))
        #expect(language.stored(row) == old.uppercased())
    }

    @Test("Whitespace around a stored name is not an edit", arguments: NameLanguage.both)
    func whitespaceIsTrimmed(_ language: NameLanguage) async throws {
        let subject = Subject()
        try await subject.importing(beforeTheCorrection(language))
        let seeded = try #require(try await subject.stored(id))
        try await subject.exercises.save(language.naming(seeded, "  \(old)\n"))

        try await subject.importing(afterTheCorrection(language))

        let row = try #require(try await subject.stored(id))
        #expect(language.stored(row) == new)
    }

    @Test("A correction the entry cannot supply leaves the stored Ukrainian name alone")
    func anEntryWithNoCurrentUkrainianNameClearsNothing() async throws {
        // The column is optional on both sides, so an entry could list a former Ukrainian name and
        // carry none of its own. Replacing then means *clearing*, which is a worse answer than the
        // retired name it removed — so the fill rule wins and the row keeps what it has.
        let subject = Subject()
        try await subject.importing(payload([AuthoredEntry(id, "Lift").translated(old)]))

        try await subject.importing(
            payload(revision: 2, [AuthoredEntry(id, "Lift").retranslated(to: nil, formerly: [old])]))

        let row = try #require(try await subject.stored(id))
        #expect(row.ukrainianName == old)
    }

    @Test("An entry renamed twice reaches a store sitting on either name", arguments: ["Second", "First"])
    func eitherFormerNameIsCorrected(_ stored: String) async throws {
        let subject = Subject()
        try await subject.importing(payload([AuthoredEntry(id, stored)]))

        try await subject.importing(
            payload(revision: 3, [AuthoredEntry(id, "Third").renamed(to: "Third", formerly: ["Second", "First"])]))

        let row = try #require(try await subject.stored(id))
        #expect(row.name == "Third")
    }

    // MARK: - Over the catalogue as it ships

    @Test("A correction reaches a store seeded by revision 3, and leaves a rename alone")
    func aCorrectionReachesAStoreSeededByRevisionThree() async throws {
        // DOD-18.5, over the frozen copy of the shipped file rather than over the shipped file
        // itself: `T-18.05` is about to edit the real one, and a fixture that moves with its subject
        // asserts nothing.
        let revisions = try CatalogueRevisions()
        let floor = BundledCatalogue.minimumExercises
        let counter = CountingExerciseRepository(wrapping: InMemoryRepositoryStack().exercises)
        let subject = Subject(over: counter)
        try await subject.importing(revisions.three, minimum: floor)
        let renamedByHand = try #require(try await subject.stored(revisions.backSquatID))
        try await subject.exercises.save(renamedByHand.edited(ukrainianName: "Присід"))

        let correction = try await subject.importing(revisions.four, minimum: floor)
        let writes = await counter.saves
        try await subject.importing(revisions.four, minimum: floor)

        let corrected = try #require(try await subject.stored(revisions.rearDeltFlyID))
        let untouched = try #require(try await subject.stored(revisions.backSquatID))
        #expect(corrected.ukrainianName == CatalogueRevisions.correctedRearDeltName)
        #expect(untouched.ukrainianName == "Присід")
        #expect(correction.writeCount == 1)
        #expect(await counter.saves == writes)
    }

    @Test("A rename of the very row the correction targets survives revision 4")
    func aRenameOnTheCorrectedRowSurvives() async throws {
        // `DOD-18.5`'s second half, on the row that can discriminate. The test above renames Back
        // Squat, whose revision-4 entry lists no former name at all — so it is kept by an empty
        // list, which is what every kept column did before former names existed, and that assertion
        // reads the same before and after this rule. Measured: a rule that ignored the match and
        // overwrote every entry carrying a list left it green.
        //
        // This is the one row revision 4 aims a correction at, so nothing but the match keeps it.
        let lifters = "Задня дельта, мій варіант"
        let revisions = try CatalogueRevisions()
        let floor = BundledCatalogue.minimumExercises
        let counter = CountingExerciseRepository(wrapping: InMemoryRepositoryStack().exercises)
        let subject = Subject(over: counter)
        try await subject.importing(revisions.three, minimum: floor)
        let seeded = try #require(try await subject.stored(revisions.rearDeltFlyID))
        try await subject.exercises.save(seeded.edited(ukrainianName: lifters))
        let writes = await counter.saves

        let correction = try await subject.importing(revisions.four, minimum: floor)

        let row = try #require(try await subject.stored(revisions.rearDeltFlyID))
        #expect(row.ukrainianName == lifters)
        #expect(correction.writeCount == 0)
        #expect(await counter.saves == writes)
    }

    @Test("A restored backup carrying the retired name is corrected by the next import")
    func aRestoredNameIsCorrected() async throws {
        // `T-1.69`: the restore runs ahead of an import, so the rows an import meets are not only
        // the ones it wrote. A backup taken before the correction carries the retired name, and the
        // row it writes is a built-in like any other — it has to be corrected the same way.
        let revisions = try CatalogueRevisions()
        let floor = BundledCatalogue.minimumExercises
        let subject = Subject()
        try await subject.importing(revisions.four, minimum: floor)
        let restored = try #require(try await subject.stored(revisions.rearDeltFlyID))
        try await subject.exercises.save(
            restored.edited(ukrainianName: CatalogueRevisions.retiredRearDeltName))

        try await subject.importing(revisions.four, minimum: floor)

        let row = try #require(try await subject.stored(revisions.rearDeltFlyID))
        #expect(row.ukrainianName == CatalogueRevisions.correctedRearDeltName)
    }
}
