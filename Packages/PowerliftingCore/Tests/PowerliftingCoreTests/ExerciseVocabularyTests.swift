// Equipment, Laterality and BarType — the three types T-0.11 invented to fill coverage gap §2,
// where `TR-0.3.1` names a field on `ExerciseEntity` that no `TR-0.2.x` defines.
//
// The case lists are the deliverable here, more than the code is: T-0.50's validator rejects any
// catalogue entry whose enum value is not one of these, and T-0.51 authors ≥80 exercises against
// them. So each type gets an explicit, literal assertion of its cases and of its raw spellings —
// derived assertions would only prove the enum agrees with itself.

import Testing

@testable import PowerliftingCore

@Suite("Equipment")
struct EquipmentTests {
    @Test("The case list is fixed, in order")
    func caseListIsFixed() {
        #expect(
            Equipment.allCases == [
                .barbell, .dumbbell, .kettlebell, .machine, .cable, .smithMachine, .bodyweight,
                .band, .other,
            ]
        )
    }

    @Test("Raw values are the persisted spelling")
    func rawValuesArePersistedSpelling() {
        #expect(Equipment.barbell.rawValue == "barbell")
        #expect(Equipment.dumbbell.rawValue == "dumbbell")
        #expect(Equipment.kettlebell.rawValue == "kettlebell")
        #expect(Equipment.machine.rawValue == "machine")
        #expect(Equipment.cable.rawValue == "cable")
        #expect(Equipment.smithMachine.rawValue == "smithMachine")
        #expect(Equipment.bodyweight.rawValue == "bodyweight")
        #expect(Equipment.band.rawValue == "band")
        #expect(Equipment.other.rawValue == "other")
    }

    @Test("Encodes as its raw string, never as an ordinal", arguments: Equipment.allCases)
    func encodesAsRawString(equipment: Equipment) throws {
        #expect(try probeEncode(equipment) == .string(equipment.rawValue))
    }

    @Test("Round-trips through Codable", arguments: Equipment.allCases)
    func roundTripsThroughCodable(equipment: Equipment) throws {
        let encoded = try probeEncode(equipment)
        #expect(try probeDecode(Equipment.self, from: encoded) == equipment)
    }

    @Test("An unknown spelling degrades to .other rather than throwing")
    func unknownSpellingDegradesToOther() throws {
        #expect(try probeDecode(Equipment.self, from: .string("sled")) == .other)
    }

    // See the equivalent test in MovementTests for why `null` is pinned here and not tolerated.
    @Test("A non-string value still throws, including null")
    func nonStringThrows() {
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(Equipment.self, from: .int(0))
        }
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(Equipment.self, from: .null)
        }
    }
}

@Suite("Laterality")
struct LateralityTests {
    @Test("The case list is fixed, in order")
    func caseListIsFixed() {
        #expect(Laterality.allCases == [.bilateral, .unilateral, .alternating])
    }

    @Test("Raw values are the persisted spelling")
    func rawValuesArePersistedSpelling() {
        #expect(Laterality.bilateral.rawValue == "bilateral")
        #expect(Laterality.unilateral.rawValue == "unilateral")
        #expect(Laterality.alternating.rawValue == "alternating")
    }

    @Test("Encodes as its raw string, never as an ordinal", arguments: Laterality.allCases)
    func encodesAsRawString(laterality: Laterality) throws {
        #expect(try probeEncode(laterality) == .string(laterality.rawValue))
    }

    @Test("Round-trips through Codable", arguments: Laterality.allCases)
    func roundTripsThroughCodable(laterality: Laterality) throws {
        let encoded = try probeEncode(laterality)
        #expect(try probeDecode(Laterality.self, from: encoded) == laterality)
    }

    // The deliberate asymmetry with the other three types. Three cases partition a physical fact
    // completely, so an unknown value is corruption rather than a newer vocabulary, and there is
    // no meaningless case to degrade onto. This test is the guard on that decision: adding a
    // fallback later has to fail here first.
    @Test("An unknown spelling throws — this type has no fallback case, on purpose")
    func unknownSpellingThrows() {
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(Laterality.self, from: .string("contralateral"))
        }
    }

    @Test("A non-string value throws, including null")
    func nonStringThrows() {
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(Laterality.self, from: .int(0))
        }
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(Laterality.self, from: .null)
        }
    }

    // The rep-counting question this type asks has the same answer for a barbell bench press and a
    // two-dumbbell bench press: ten reps is ten reps. Added on review (T-0.11) — the doc comment
    // previously said `bilateral` meant "sharing one load", which excluded every two-dumbbell
    // exercise and left T-0.51's catalogue with nowhere to put them. This pins the corrected
    // reading so the next person to touch the doc comment has to disagree with a test.
    @Test("Two-implement work is bilateral — the type does not model implement count")
    func twoImplementWorkIsBilateral() {
        #expect(Laterality.allCases.count == 3)
        #expect(Laterality(rawValue: "bilateralIndependent") == nil)
    }
}

@Suite("BarType")
struct BarTypeTests {
    @Test("The case list is fixed, in order")
    func caseListIsFixed() {
        #expect(
            BarType.allCases == [
                .standard, .ezCurl, .trap, .safetySquat, .cambered, .swiss, .noBar, .other,
            ]
        )
    }

    @Test("Raw values are the persisted spelling")
    func rawValuesArePersistedSpelling() {
        #expect(BarType.standard.rawValue == "standard")
        #expect(BarType.ezCurl.rawValue == "ezCurl")
        #expect(BarType.trap.rawValue == "trap")
        #expect(BarType.safetySquat.rawValue == "safetySquat")
        #expect(BarType.cambered.rawValue == "cambered")
        #expect(BarType.swiss.rawValue == "swiss")
        #expect(BarType.noBar.rawValue == "noBar")
        #expect(BarType.other.rawValue == "other")
    }

    // `BarType.none` would collide with `Optional.none` at every call site typed `BarType?`, and
    // Swift resolves that in favour of `Optional` with a warning — a build failure under
    // warnings-as-errors. The case is called `noBar` so that cannot happen.
    //
    // Renaming the case back would be caught by the compiler long before this test runs, since
    // every `.noBar` reference above stops resolving. What a compiler cannot catch is someone
    // keeping the case name and giving it an explicit `= "none"` raw value, which reintroduces the
    // collision the moment anyone writes `BarType(rawValue:)`-shaped code against it. That is the
    // hole this assertion covers, and it is the only one worth a test.
    @Test("No case persists as the string `none`")
    func noCasePersistsAsNone() {
        #expect(BarType(rawValue: "none") == nil)
    }

    @Test("Encodes as its raw string, never as an ordinal", arguments: BarType.allCases)
    func encodesAsRawString(barType: BarType) throws {
        #expect(try probeEncode(barType) == .string(barType.rawValue))
    }

    @Test("Round-trips through Codable", arguments: BarType.allCases)
    func roundTripsThroughCodable(barType: BarType) throws {
        let encoded = try probeEncode(barType)
        #expect(try probeDecode(BarType.self, from: encoded) == barType)
    }

    @Test("An unknown spelling degrades to .other rather than throwing")
    func unknownSpellingDegradesToOther() throws {
        #expect(try probeDecode(BarType.self, from: .string("axle")) == .other)
    }

    // See the equivalent test in MovementTests for why `null` is pinned here and not tolerated.
    @Test("A non-string value still throws, including null")
    func nonStringThrows() {
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(BarType.self, from: .int(0))
        }
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(BarType.self, from: .null)
        }
    }
}
