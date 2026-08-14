import PowerliftingCore
import SeedContent
import Testing

/// One spelling per field that belongs to that vocabulary and to no other.
///
/// The values come from the domain types rather than from string literals, which is what makes this
/// a test of the wiring: a field resolving through the wrong type accepts the wrong anchor.
let vocabularyAnchors: [(field: SeedVocabularyField, value: String)] = [
    (.movement, Movement.squat.rawValue),
    (.equipment, Equipment.barbell.rawValue),
    (.laterality, Laterality.alternating.rawValue),
    (.barType, BarType.ezCurl.rawValue),
]

@Suite("Vocabulary fields")
struct SeedVocabularyFieldTests {
    @Test("Every field is anchored")
    func everyFieldIsAnchored() {
        #expect(vocabularyAnchors.map(\.field) == SeedVocabularyField.allCases)
    }

    @Test("An anchor is accepted by its own field and by no other", arguments: vocabularyAnchors)
    func anchorIsAcceptedByItsOwnFieldAlone(_ anchor: (field: SeedVocabularyField, value: String)) {
        #expect(anchor.field.accepts(anchor.value))
        for other in SeedVocabularyField.allCases where other != anchor.field {
            #expect(!other.accepts(anchor.value))
        }
    }

    @Test("A field accepts exactly the spellings it publishes", arguments: SeedVocabularyField.allCases)
    func acceptedValuesAgreeWithTheType(_ field: SeedVocabularyField) {
        #expect(!field.acceptedValues.isEmpty)
        for value in field.acceptedValues {
            #expect(field.accepts(value))
        }
        #expect(!field.accepts(field.acceptedValues.joined()))
    }

    // `other` is a legitimate authored value for an accessory, not only a decode fallback, and
    // `noBar` — not `none`, and not an absent field — is what an exercise using no bar says. Named
    // through the domain types, so renaming either case fails here as well as at every call site.
    @Test("`other` and `noBar` are authored values")
    func authoredCatchAllsAreAccepted() {
        #expect(SeedVocabularyField.movement.accepts(Movement.other.rawValue))
        #expect(SeedVocabularyField.equipment.accepts(Equipment.other.rawValue))
        #expect(SeedVocabularyField.barType.accepts(BarType.other.rawValue))
        #expect(SeedVocabularyField.barType.accepts(BarType.noBar.rawValue))
    }
}
