import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

// Split out of `RecordCodingTests.swift` for size, along the same suite boundary the
// later-column suite was split on: that file reached the 500-line ceiling again once
// `FR-16.7`'s training-max history record gained a key list of its own. Nothing here changed
// in the move — a round trip is rules 1, 2, 3 and 6 read end to end, where the key tests left
// behind read rule 1 alone.

@Suite("Records round-trip through JSON")
struct RecordJSONRoundTripTests {
    // Every record, anchored on the whole value rather than on a field, so a conformance that
    // dropped a key fails here as well as in the key-spelling suite.

    private static func roundTrip<R: StoredRecord>(_ record: R) throws -> R {
        try JSONDecoder().decode(R.self, from: try JSONEncoder().encode(record))
    }

    @Test("Every record survives encode and decode")
    func everyRecordSurvives() throws {
        #expect(try Self.roundTrip(codingExercise()) == codingExercise())
        #expect(try Self.roundTrip(codingSession()) == codingSession())
        #expect(try Self.roundTrip(codingExerciseEntry()) == codingExerciseEntry())
        #expect(try Self.roundTrip(codingSetEntry()) == codingSetEntry())
        #expect(try Self.roundTrip(codingBodyweightEntry()) == codingBodyweightEntry())
        #expect(try Self.roundTrip(codingTrainingMaxEntry()) == codingTrainingMaxEntry())
        #expect(
            try Self.roundTrip(codingTrainingMaxHistoryEntry())
                == codingTrainingMaxHistoryEntry())
        #expect(try Self.roundTrip(codingEquipmentProfile()) == codingEquipmentProfile())
        #expect(try Self.roundTrip(codingUserSettings()) == codingUserSettings())
        // FR-16.3.2's chosen cells are two parallel columns on the wire, and pairing them up again
        // is the one thing about this record's format that a plain field comparison would miss.
        var configured = codingUserSettings()
        configured.recentRecordsSchemes = .chosen([
            RecordScheme(reps: 5, sets: 5), RecordScheme(reps: 3, sets: 1),
        ])
        #expect(try Self.roundTrip(configured) == configured)
        #expect(try Self.roundTrip(codingPersonalRecordCache()) == codingPersonalRecordCache())
        #expect(try Self.roundTrip(codingRoutine()) == codingRoutine())
        #expect(try Self.roundTrip(codingRoutineExercise()) == codingRoutineExercise())
        #expect(try Self.roundTrip(codingRoutineTargetGroup()) == codingRoutineTargetGroup())
        #expect(try Self.roundTrip(codingProgram()) == codingProgram())
        #expect(try Self.roundTrip(codingProgramDay()) == codingProgramDay())
        #expect(try Self.roundTrip(codingProgramRun()) == codingProgramRun())
        #expect(try Self.roundTrip(codingPlannedTargetGroup()) == codingPlannedTargetGroup())
    }

    // FR-15.2.2 on the wire: a blank target is an absent key that decodes back to `nil`, not a
    // zero and not a null. This is the one optional in the layer whose two readings are different
    // *training* facts rather than a present-or-absent field, so it is pinned separately from the
    // generic omit rule above.
    @Test("A blank planned weight is omitted, and comes back blank rather than as zero")
    func aBlankPlannedWeightIsOmitted() throws {
        let record = codingPlannedTargetGroup(grams: nil)
        let json = try jsonText(of: record)

        #expect(!json.contains("targetWeight"))
        #expect(try Self.roundTrip(record).targetWeight == nil)
        // The rest of the group is prescribed either way — a blank weight is not a blank plan.
        #expect(try Self.roundTrip(record).targetReps == 4)
    }

    // A nil optional is omitted rather than written as null, and the omission decodes back to nil.
    // Anchored on the encoded text as well as on the decoded value: asserting only the round trip
    // would pass for a conformance that wrote `"rpe":null`.
    @Test("A nil optional is omitted, and comes back nil")
    func nilOptionalsAreOmitted() throws {
        let record = codingSetEntry(rpe: nil)
        let json = try jsonText(of: record)

        #expect(!json.contains("rpe"))
        #expect(try Self.roundTrip(record).rpe == nil)
    }

    // The other half of that rule: a payload written by something that does emit nulls still
    // decodes. `decodeIfPresent` gives this for free, which is exactly why it is worth pinning —
    // nothing in the source says it, and a hand-rolled decoder could lose it.
    @Test("An explicit null decodes as an absent value")
    func explicitNullDecodes() throws {
        let json = """
            {"id":"0f7b6a5c-1111-4222-8333-444455556666","createdAt":0,"updatedAt":0,
             "deletedAt":null,"date":0,"weight":82400,"source":"manual"}
            """
        let record = try JSONDecoder().decode(BodyweightEntry.self, from: Data(json.utf8))

        #expect(record.deletedAt == nil)
        #expect(record.isSoftDeleted == false)
    }

    // `FR-1.14.2` added a column to a wire format that already has backups written against it
    // (`FR-1.11.4`), so this is the shape of every payload a user restores from today. Anchored on a
    // neighbouring field as well: a decoder that threw the record away and rebuilt an empty one
    // would satisfy the `nil` on its own.
    @Test("A payload written before the Ukrainian name existed decodes without one")
    func absentUkrainianNameDecodes() throws {
        // Rebuilt through `JSONSerialization` rather than by deleting a substring: `JSONEncoder`
        // emits keys in per-process hash order, so whether this key carries a trailing comma varies
        // between runs and a textual removal would be flaky rather than strict.
        let encoded = try JSONEncoder().encode(codingExercise())
        var object = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object.removeValue(forKey: "ukrainianName") != nil, "the fixture has no key to drop")

        let older = try JSONSerialization.data(withJSONObject: object)
        let record = try JSONDecoder().decode(Exercise.self, from: older)

        #expect(record.ukrainianName == nil)
        #expect(record.name == "Low-bar back squat")
    }

    @Test("An exercise with no Ukrainian name omits the key rather than writing null")
    func absentUkrainianNameIsOmitted() throws {
        let record = makeExercise()
        let json = try jsonText(of: record)

        #expect(!json.contains("ukrainianName"))
        #expect(try Self.roundTrip(record).ukrainianName == nil)
    }
}
