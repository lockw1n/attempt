import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2).

/// A second vocabulary, existing only to prove `OpenVocabulary` is generic rather than welded to
/// `SetModifierTerm`. T-0.20 needs it for a different `Term` (its notes asked for exactly that),
/// and "it happens to work for the one type that uses it" is not evidence of that.
private enum ProbeTerm: String, Sendable, Hashable, CaseIterable {
    case alpha
    case beta
}

private typealias ProbeVocabulary = OpenVocabulary<ProbeTerm>

@Suite("OpenVocabulary — recognised and unrecognised terms")
struct OpenVocabularyTests {
    @Test("A known term keeps its raw spelling and is recognised")
    func knownTermRoundTripsThroughRawValue() {
        let value = SetModifier(.belt)
        #expect(value.rawValue == "belt")
        #expect(value.known == .belt)
        #expect(value.isKnown)
    }

    @Test("An unrecognised spelling is preserved verbatim and reports itself unknown")
    func unknownSpellingIsPreserved() {
        // The whole reason this type exists: nothing upstream re-supplies a set modifier, so a
        // value from a newer version or a user-configured list (FR-1.2.8) must survive intact.
        let value = SetModifier(rawValue: "chains")
        #expect(value.rawValue == "chains")
        #expect(value.known == nil)
        #expect(!value.isKnown)
    }

    @Test("Nothing about the raw spelling is normalised", arguments: ["", "Belt", " belt", "belt "])
    func rawSpellingIsNotNormalised(raw: String) {
        // Normalising would rewrite a value the app cannot interpret, which G-1.6 forbids for
        // logged data — and it would make "Belt" indistinguishable from "belt" on the way back.
        let value = SetModifier(rawValue: raw)
        #expect(value.rawValue == raw)
        #expect(value.known == nil)
    }

    @Test("Equality and hashing are the raw spelling, so there is only one representation")
    func equalityIsTheRawSpelling() {
        // The argument for a struct over a `known`/`unknown` enum: with two cases,
        // `.unknown("belt")` and `.known(.belt)` would compare unequal while encoding identically.
        #expect(SetModifier(.belt) == SetModifier(rawValue: "belt"))
        #expect(Set([SetModifier(.belt), SetModifier(rawValue: "belt")]).count == 1)
        #expect(SetModifier(.belt) != SetModifier(.sleeves))
    }

    @Test("Description is the raw spelling")
    func descriptionIsTheRawSpelling() {
        #expect(SetModifier(.touchAndGo).description == "touchAndGo")
        #expect(SetModifier(rawValue: "chains").description == "chains")
    }

    @Test("It is generic over the vocabulary, not tied to SetModifierTerm")
    func worksForASecondVocabulary() {
        #expect(ProbeVocabulary(.alpha).known == .alpha)
        #expect(ProbeVocabulary(rawValue: "gamma").known == nil)
        // `Term` decides only what `known` recognises: "belt" is a known SetModifier and an
        // unknown ProbeTerm, from the same raw string. That is the generic parameter doing work,
        // rather than being carried along unused.
        #expect(ProbeVocabulary(rawValue: "belt").known == nil)
        #expect(SetModifier(rawValue: "belt").known == .belt)
    }

    @Test("Equality follows String, so two canonically-equivalent spellings are one modifier")
    func canonicallyEquivalentSpellingsCompareEqual() {
        // Measured, not assumed (2026-08-04). `String` compares by canonical equivalence, so a
        // precomposed é and a decomposed one are `==` here while their UTF-8 differs. Consequences,
        // both accepted for Phase 0 and recorded in T-0.12's notes: `SetRecord.modifiers` dedupes
        // them to one, and *which* spelling survives follows input order — so two records that
        // compare equal can encode to different bytes. The encode → decode → encode contract is
        // unaffected: whatever string is stored round-trips exactly.
        let precomposed = SetModifier(rawValue: "caf\u{00E9}")
        let decomposed = SetModifier(rawValue: "cafe\u{0301}")
        #expect(precomposed == decomposed)
        #expect(Array(precomposed.rawValue.utf8) != Array(decomposed.rawValue.utf8))
    }
}

@Suite("OpenVocabulary — wire format")
struct OpenVocabularyCodableTests {
    @Test("Encodes as a bare string, not a wrapper object")
    func encodesAsBareString() throws {
        // Pinned, not incidental: synthesis over the single stored property would have produced
        // `{"rawValue": "belt"}`, and the bare string is what nests into an array of modifiers
        // without a layer of noise. Changing it is a storage migration.
        #expect(try probeEncode(SetModifier(.belt)) == .string("belt"))
        #expect(try probeEncode(SetModifier(rawValue: "chains")) == .string("chains"))
    }

    @Test("Round-trips every known term")
    func roundTripsEveryKnownTerm() throws {
        for term in SetModifierTerm.allCases {
            let value = SetModifier(term)
            #expect(try probeDecode(SetModifier.self, from: try probeEncode(value)) == value)
        }
    }

    @Test("An unrecognised spelling decodes without throwing and re-encodes unchanged")
    func unknownSpellingSurvivesARoundTrip() throws {
        // Deliberately the opposite of Movement/Equipment/BarType, which degrade to `.other`, and
        // of Laterality/RoundingStrategy, which throw. See OpenVocabulary's two-question rule.
        let decoded = try probeDecode(SetModifier.self, from: .string("chains"))
        #expect(decoded.rawValue == "chains")
        #expect(decoded.known == nil)
        #expect(try probeEncode(decoded) == .string("chains"))
    }

    @Test("A non-string value throws")
    func nonStringThrows() {
        // Corruption, not a newer vocabulary — the same line Movement.init(from:) draws.
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(SetModifier.self, from: .int(1))
        }
    }
}

@Suite("SetModifierTerm")
struct SetModifierTermTests {
    @Test("The nine FR-1.2.8 modifiers exist with their persisted spellings")
    func theNineModifiersArePresent() {
        // The case list is a storage contract: renaming one is a migration, and T-0.31 stores
        // these strings. Pinned by assertion rather than left to whoever edits the enum next.
        #expect(
            SetModifierTerm.allCases.map(\.rawValue) == [
                "belt", "sleeves", "wraps", "straps", "paused",
                "tempo", "touchAndGo", "deficit", "board",
            ])
    }

    @Test("Every raw value reconstructs its case")
    func rawValuesReconstructTheirCases() {
        for term in SetModifierTerm.allCases {
            #expect(SetModifierTerm(rawValue: term.rawValue) == term)
        }
    }
}
