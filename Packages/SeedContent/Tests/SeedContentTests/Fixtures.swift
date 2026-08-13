import Foundation
import SeedContent
import Testing

/// The bytes of a fixture, loaded the way the shipped file will be.
func fixture(_ name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
        "no fixture named \(name).json")
    return try Data(contentsOf: url)
}

/// A file broken on purpose, and the one failure it must produce.
struct BrokenFixture: Sendable, CustomTestStringConvertible {
    let file: String
    let kind: SeedValidationFailure.Kind
    let expected: SeedValidationFailure?

    var testDescription: String { file }

    init(_ file: String, _ expected: SeedValidationFailure) {
        self.file = file
        self.kind = expected.kind
        self.expected = expected
    }

    /// For a failure carrying a decoder's own wording, which is the toolchain's to phrase and not
    /// this suite's to pin. Only the kind is asserted.
    init(_ file: String, kind: SeedValidationFailure.Kind) {
        self.file = file
        self.kind = kind
        self.expected = nil
    }
}

/// One fixture per failure mode, and the suite walks this rather than naming the modes.
///
/// The four vocabulary entries are why: `laterality` is the only one of the four whose domain type
/// throws on an unrecognised spelling, so a validator exercised on it alone looks like it works.
/// `everyFailureKindHasAFixture` and `everyVocabularyFieldHasAFixture` are what stop a twelfth
/// failure or a fifth vocabulary from being half-covered.
let brokenFixtures: [BrokenFixture] = [
    BrokenFixture("duplicate-id", .duplicateID(squatID)),
    BrokenFixture("dangling-parent", .danglingParent(exercise: frontSquatID, parent: absentID)),
    BrokenFixture("parent-cycle", .parentCycle([squatID, frontSquatID])),
    BrokenFixture("self-parent", .parentCycle([squatID])),
    // A cycle the walk reaches through a tail, so the report is the cycle rather than the route to
    // it. Both fixtures above have the cycle at the start of the walk, and a mutation probe found
    // that between them they could not tell the two apart.
    BrokenFixture("parent-cycle-with-tail", .parentCycle([frontSquatID, dumbbellBenchID])),
    // An entry hanging *below* a cycle, which is what makes the walk's memo load-bearing: without
    // it the second walk re-enters the same cycle and reports it twice. In every fixture above, the
    // walk that finds the cycle also reaches every other entry, so a probe deleting the memo
    // survived them all.
    BrokenFixture("cycle-with-descendant", .parentCycle([squatID, frontSquatID])),
    BrokenFixture(
        "unknown-movement",
        .unknownVocabulary(exercise: squatID, field: .movement, value: "sled")),
    BrokenFixture(
        "unknown-equipment",
        .unknownVocabulary(exercise: squatID, field: .equipment, value: "chains")),
    BrokenFixture(
        "unknown-laterality",
        .unknownVocabulary(exercise: squatID, field: .laterality, value: "unilaterall")),
    // `none` rather than a nonsense word: `BarType`'s case is `noBar`, and `none` is the spelling
    // an author reaches for.
    BrokenFixture(
        "unknown-bar-type",
        .unknownVocabulary(exercise: squatID, field: .barType, value: "none")),
    BrokenFixture("zero-implement-count", .nonPositiveImplementCount(exercise: squatID, count: 0)),
    BrokenFixture("unsupported-schema-version", .unsupportedSchemaVersion(2)),
    BrokenFixture("non-positive-revision", .nonPositiveRevision(0)),
    BrokenFixture("blank-name", .blankName(squatID)),
    BrokenFixture("too-few-exercises", .tooFewExercises(count: 0, minimum: 1)),
    // Both containers reject an unrecognised key, and both are exercised: the entry is where a typo
    // actually happens, the root is where nothing would ever notice one. The entry's location is
    // asserted rather than only its key, because a bare `parent` is not searchable in a file where
    // every variation row carries `parentExerciseID`.
    BrokenFixture(
        "unrecognised-entry-field", .unrecognisedField(name: "parent", location: "exercises[0]")),
    BrokenFixture("unrecognised-root-field", .unrecognisedField(name: "version", location: "")),
    // Two unrecognised keys in one object, which yields one failure rather than a list: decoding
    // stops at the first, so there is nothing further to report. The *choice* of `edition` over
    // `version` is not pinned here — the decoder sorts `allKeys` before this code sees them, so no
    // payload can tell a sorted pick from an arbitrary one. `SeedDecodingTests` pins that.
    BrokenFixture("unrecognised-root-fields", .unrecognisedField(name: "edition", location: "")),
    BrokenFixture("malformed-uuid", kind: .undecodable),
    BrokenFixture("missing-field", kind: .undecodable),
]

let squatID = fixtureID("11111111-1111-4111-8111-111111111111")
let frontSquatID = fixtureID("22222222-2222-4222-8222-222222222222")
let dumbbellBenchID = fixtureID("33333333-3333-4333-8333-333333333333")
let sledPushID = fixtureID("44444444-4444-4444-8444-444444444444")
let absentID = fixtureID("99999999-9999-4999-8999-999999999999")

/// The same literal appears in the JSON, so a mistyped one here fails every assertion naming it
/// rather than quietly matching nothing.
private func fixtureID(_ string: String) -> UUID {
    UUID(uuidString: string) ?? UUID()
}
