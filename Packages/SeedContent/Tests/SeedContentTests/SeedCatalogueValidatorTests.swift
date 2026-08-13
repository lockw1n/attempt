import Foundation
import SeedContent
import Testing

// TR-0.5.1. The failure modes are a list, and this suite walks it: `brokenFixtures` is the list,
// two guards below hold it closed, and no test here names a failure mode on its own.

@Suite("Seed catalogue validator")
struct SeedCatalogueValidatorTests {
    @Test("A well-formed payload produces no failures")
    func validFixturePasses() throws {
        #expect(SeedCatalogueValidator.validate(try fixture("valid")).isEmpty)
    }

    @Test(
        "Each broken fixture is rejected, with the failure it was written for",
        arguments: brokenFixtures)
    func brokenFixtureIsRejected(_ broken: BrokenFixture) throws {
        let failures = SeedCatalogueValidator.validate(try fixture(broken.file))

        // Comparing the kinds pins the count as well: a fixture broken twice over is a fixture
        // that proves less than it claims.
        #expect(failures.map(\.kind) == [broken.kind])
        if let expected = broken.expected {
            #expect(failures == [expected])
        }
    }

    @Test("Every failure kind has a fixture")
    func everyFailureKindHasAFixture() {
        #expect(Set(brokenFixtures.map(\.kind)) == Set(SeedValidationFailure.Kind.allCases))
    }

    @Test("Every vocabulary field has a fixture")
    func everyVocabularyFieldHasAFixture() {
        let covered = brokenFixtures.compactMap { broken -> SeedVocabularyField? in
            guard case .unknownVocabulary(_, let field, _)? = broken.expected else { return nil }
            return field
        }
        #expect(Set(covered) == Set(SeedVocabularyField.allCases))
    }

    @Test("Every failure says something an author can act on", arguments: brokenFixtures)
    func failureDescribesItself(_ broken: BrokenFixture) throws {
        let failure = try #require(
            SeedCatalogueValidator.validate(try fixture(broken.file)).first)

        #expect(!failure.description.isEmpty)
        // The vocabulary failure is the one whose message has to do work: it is the only place the
        // accepted spellings are ever shown, and they are derived rather than written down.
        if case .unknownVocabulary(_, let field, let value) = failure {
            #expect(failure.description.contains(value))
            for accepted in field.acceptedValues {
                #expect(failure.description.contains(accepted))
            }
        }
    }

    @Test("A minimum the payload does not meet is a failure naming both counts")
    func minimumExercisesIsEnforced() throws {
        let failures = SeedCatalogueValidator.validate(try fixture("valid"), minimumExercises: 5)

        #expect(failures == [.tooFewExercises(count: 4, minimum: 5)])
    }
}

@Suite("Seed payload shape")
struct SeedCatalogueShapeTests {
    private func decodeValid() throws -> SeedCatalogue {
        try JSONDecoder().decode(SeedCatalogue.self, from: try fixture("valid"))
    }

    // The keys are a published contract (TR-0.5.2), so they are pinned by a file rather than by a
    // round trip: the `…RawValue` suffixes are a Swift-side distinction and must not reach the wire.
    @Test("The payload decodes on the file's keys")
    func payloadDecodesOnTheFilesKeys() throws {
        let catalogue = try decodeValid()

        #expect(catalogue.schemaVersion == SeedCatalogue.supportedSchemaVersion)
        #expect(catalogue.revision == 1)
        #expect(catalogue.exercises.map(\.id) == [squatID, frontSquatID, dumbbellBenchID, sledPushID])
        #expect(catalogue.exercises.map(\.name).first == "Back Squat")
        #expect(catalogue.exercises.map(\.movementRawValue) == ["squat", "squat", "bench", "other"])
        #expect(catalogue.exercises.map(\.barTypeRawValue).last == "other")
    }

    @Test("A variation carries its parent and a root carries none")
    func parentLinkageDecodes() throws {
        #expect(try decodeValid().exercises.map(\.parentExerciseID) == [nil, squatID, nil, nil])
    }

    // Both halves matter: an absent implement count must resolve to one AND stay absent, because an
    // author only says anything on the multi-implement entries.
    @Test("An absent implement count is one, and stays absent")
    func absentImplementCountIsOne() throws {
        let exercises = try decodeValid().exercises

        #expect(exercises.map(\.implementCount) == [nil, nil, 2, nil])
        #expect(exercises.map(\.implements) == [1, 1, 2, 1])
    }

    @Test("rawValue(for:) reads the field it names")
    func rawValueAccessorReadsItsOwnField() throws {
        let entry = try #require(try decodeValid().exercises.first { $0.id == dumbbellBenchID })

        // This entry's four spellings belong to one vocabulary each, so a crossed accessor cannot
        // produce a value the field it was asked about accepts.
        for field in SeedVocabularyField.allCases {
            #expect(field.accepts(entry.rawValue(for: field)))
        }
        let spellings = SeedVocabularyField.allCases.map { entry.rawValue(for: $0) }
        #expect(Set(spellings).count == SeedVocabularyField.allCases.count)
    }
}
