import Testing

@testable import PowerliftingCore

@Suite("Movement")
struct MovementTests {
    @Test("The six cases are exactly the ones TR-0.2.2 lists, in order")
    func casesMatchTheRequirement() {
        #expect(Movement.allCases == [.squat, .bench, .deadlift, .overheadPress, .row, .other])
    }

    // The assertion that matters most in this file. These strings are written into
    // ExerciseEntity (TR-0.3.1) and exercises.json (TR-0.5.1); changing one orphans every
    // exercise already carrying it, and with it every set logged against that exercise. Spelled
    // out literally rather than derived from `rawValue`, so that a rename fails here rather than
    // agreeing with itself.
    @Test("Raw values are the persisted spelling")
    func rawValuesArePersistedSpelling() {
        #expect(Movement.squat.rawValue == "squat")
        #expect(Movement.bench.rawValue == "bench")
        #expect(Movement.deadlift.rawValue == "deadlift")
        #expect(Movement.overheadPress.rawValue == "overheadPress")
        #expect(Movement.row.rawValue == "row")
        #expect(Movement.other.rawValue == "other")
    }

    @Test("Encodes as its raw string, never as an ordinal", arguments: Movement.allCases)
    func encodesAsRawString(movement: Movement) throws {
        #expect(try probeEncode(movement) == .string(movement.rawValue))
    }

    @Test("Round-trips through Codable", arguments: Movement.allCases)
    func roundTripsThroughCodable(movement: Movement) throws {
        let encoded = try probeEncode(movement)
        #expect(try probeDecode(Movement.self, from: encoded) == movement)
    }

    @Test("An unknown spelling degrades to .other rather than throwing")
    func unknownSpellingDegradesToOther() throws {
        #expect(try probeDecode(Movement.self, from: .string("hipThrust")) == .other)
        #expect(try probeDecode(Movement.self, from: .string("")) == .other)
    }

    // Degrading is for a newer *vocabulary*, not for a broken payload: a movement that arrives as
    // a number is corruption, and swallowing it would hide a wire-format change.
    //
    // `null` throws too, and that is a boundary worth pinning rather than a detail. T-0.50's
    // validator needs a missing `movement` rejected as a malformed catalogue entry — but `G-2.5`
    // makes every CloudKit property optional-or-defaulted, so a synced record can carry one, and
    // there a throw costs the record that the `.other` fallback exists to protect. The two
    // contexts want opposite answers from one decoder, so this type gives the strict one and the
    // entity layer decides what to do with it (recorded in T-0.31's notes). If this assertion is
    // ever relaxed, T-0.50's "unknown enum" fixture stops failing and nobody finds out.
    @Test("A non-string value still throws, including null")
    func nonStringThrows() {
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(Movement.self, from: .int(0))
        }
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(Movement.self, from: .null)
        }
    }
}
