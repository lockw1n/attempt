import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@Suite("The record wire format")
struct RecordCodingKeyTests {
    // Key spelling, pinned per record, plus the completeness of the list — no key silently added,
    // dropped or respelled. These literals are the storage contract (TR-0.4.4, TR-5.4), so a
    // failing assertion here is a migration rather than a rename.
    //
    // **Key order is deliberately not asserted, and the reason is a measurement rather than a
    // preference.** `JSONEncoder` accumulates a keyed container into a dictionary and emits it in
    // Swift's per-process hash order, which differs between runs of the same binary — so an
    // order assertion through this encoder would be flaky rather than strict. Declaration order is
    // a property of the hand-written conformances, observable only through an order-preserving
    // encoder, and the byte contract that would need one belongs with TR-2.1 and TR-5.4. See
    // `encodedKeys(of:)`.
    //
    // Every fixture has all of its optionals populated, because an omitted key is not a missing
    // one: the omit-when-nil rule has its own test.

    @Test("An exercise writes sixteen keys")
    func exerciseKeys() throws {
        #expect(
            try encodedKeys(of: codingExercise()) == [
                "barType", "createdAt", "deletedAt", "equipment", "id", "implementCount",
                "isArchived", "isCustom", "laterality", "manualE1RM", "movement", "name", "notes",
                "parentExerciseID", "ukrainianName", "updatedAt",
            ])
    }

    @Test("A session writes eleven keys")
    func sessionKeys() throws {
        #expect(
            try encodedKeys(of: codingSession()) == [
                "bodyweight", "createdAt", "date", "deletedAt", "endedAt", "id", "notes",
                "programRunID", "scheduledWorkoutID", "startedAt", "updatedAt",
            ])
    }

    @Test("An exercise entry writes nine keys")
    func exerciseEntryKeys() throws {
        #expect(
            try encodedKeys(of: codingExerciseEntry()) == [
                "createdAt", "deletedAt", "exerciseID", "id", "isMarkedDone", "notes", "order",
                "sessionID", "updatedAt",
            ])
    }

    @Test("A set writes seventeen keys")
    func setEntryKeys() throws {
        #expect(
            try encodedKeys(of: codingSetEntry()) == [
                "completedAt", "createdAt", "deletedAt", "entryID", "id", "isCompleted", "isWarmup",
                "modifiers", "notes", "order", "reps", "rir", "rpe", "targetReps", "targetWeight",
                "updatedAt", "weight",
            ])
    }

    @Test("A bodyweight reading writes seven keys")
    func bodyweightKeys() throws {
        #expect(
            try encodedKeys(of: codingBodyweightEntry()) == [
                "createdAt", "date", "deletedAt", "id", "source", "updatedAt", "weight",
            ])
    }

    @Test("A training-max entry writes thirteen keys")
    func trainingMaxKeys() throws {
        #expect(
            try encodedKeys(of: codingTrainingMaxEntry()) == [
                "createdAt", "deletedAt", "effectiveFrom", "exerciseID", "id", "manualWeight",
                "percentage", "progressionIncrement", "roundingIncrement", "roundingStrategy",
                "source", "sourceRepCount", "updatedAt",
            ])
    }

    @Test("A profile writes ten keys")
    func profileKeys() throws {
        #expect(
            try encodedKeys(of: codingEquipmentProfile()) == [
                "barWeight", "collarWeight", "createdAt", "deletedAt", "id", "isDefault", "name",
                "platePairCounts", "plates", "updatedAt",
            ])
    }

    @Test("Settings write fourteen keys")
    func settingsKeys() throws {
        #expect(
            try encodedKeys(of: codingUserSettings()) == [
                "createdAt", "defaultRoundingIncrement", "defaultRoundingStrategy", "deletedAt",
                "displayUnit", "e1RMFormula", "e1RMLookbackDays", "id", "keepScreenAwake",
                "recentRecordsScope", "recentRecordsShowsBaselines", "theme", "updatedAt", "userID",
            ])
    }

    /// `FR-16.3.2`'s chosen cells are two parallel columns, on the wire as in the store, and both
    /// are absent where the schemes are derived — which is what makes an unconfigured row short.
    @Test("Chosen schemes write two parallel key columns; derived schemes write neither")
    func settingsSchemeKeys() throws {
        var configured = codingUserSettings()
        configured.recentRecordsSchemes = .chosen([
            RecordScheme(reps: 5, sets: 5), RecordScheme(reps: 3, sets: 1),
        ])

        let keys = try encodedKeys(of: configured)
        #expect(keys.contains("recentRecordsSchemeReps"))
        #expect(keys.contains("recentRecordsSchemeSets"))
        #expect(try !encodedKeys(of: codingUserSettings()).contains("recentRecordsSchemeReps"))
    }

    /// The two optional preferences are absent rather than null where the user never chose, and
    /// present the moment they did — the rule that lets a never-configured row stay short.
    @Test("A chosen display step joins the keys; an unchosen one writes nothing")
    func settingsPrecisionKey() throws {
        var configured = codingUserSettings()
        configured.displayPrecision = .quarter
        #expect(try encodedKeys(of: configured).contains("displayPrecision"))
        #expect(try !encodedKeys(of: codingUserSettings()).contains("displayPrecision"))
    }

    @Test("A cached record writes twelve keys")
    func cacheKeys() throws {
        #expect(
            try encodedKeys(of: codingPersonalRecordCache()) == [
                "achievedAt", "computationVersion", "createdAt", "deletedAt", "exerciseID", "id",
                "previousWeight", "repCount", "setCount", "sourceSetID", "updatedAt", "weight",
            ])
    }

    // TR-16.1's optional column, on `deletedAt`'s rule: a baseline writes no key at all rather than
    // a zero, since `Weight` is signed and zero is a real beaten load (FR-16.2.3).
    @Test("A baseline record writes no beaten load")
    func baselineCacheKeys() throws {
        let baseline = PersonalRecordCache(
            id: codingID,
            createdAt: codingCreatedAt,
            updatedAt: codingUpdatedAt,
            deletedAt: codingDeletedAt,
            exerciseID: codingJoinID,
            repCount: 3,
            weight: Weight(grams: 180_000),
            sourceSetID: codingJoinID,
            achievedAt: codingCreatedAt,
            computationVersion: 1)

        #expect(try !encodedKeys(of: baseline).contains("previousWeight"))
        #expect(try encodedKeys(of: baseline).contains("setCount"))
    }

    @Test("A routine writes five keys")
    func routineKeys() throws {
        #expect(
            try encodedKeys(of: codingRoutine()) == [
                "createdAt", "deletedAt", "id", "name", "updatedAt",
            ])
    }

    @Test("A routine exercise slot writes seven keys")
    func routineExerciseKeys() throws {
        #expect(
            try encodedKeys(of: codingRoutineExercise()) == [
                "createdAt", "deletedAt", "exerciseID", "id", "order", "routineID", "updatedAt",
            ])
    }

    @Test("A routine target group writes nine keys")
    func routineTargetGroupKeys() throws {
        #expect(
            try encodedKeys(of: codingRoutineTargetGroup()) == [
                "createdAt", "deletedAt", "id", "order", "routineExerciseID", "targetReps",
                "targetSets", "targetWeight", "updatedAt",
            ])
    }

    @Test("A planned target group writes nine keys")
    func plannedTargetGroupKeys() throws {
        #expect(
            try encodedKeys(of: codingPlannedTargetGroup()) == [
                "createdAt", "deletedAt", "exerciseEntryID", "id", "order", "targetReps",
                "targetSets", "targetWeight", "updatedAt",
            ])
    }
}

@Suite("Nested wire formats are not re-wrapped")
struct RecordNestedShapeTests {
    // The three shapes this layer inherits rather than invents, asserted against literal substrings
    // so that a wrapper object appearing around any of them fails here rather than in Phase 5.
    //
    // The date representation is deliberately *not* asserted: it is the encoder's configuration,
    // and choosing one belongs to whoever writes the first real payload (TR-2.1, TR-5.4).

    @Test("A weight is a bare integer of grams and a modifier a bare string")
    func nestedValuesAreBare() throws {
        let json = try jsonText(of: codingSetEntry())

        #expect(json.contains("\"weight\":142500"))
        #expect(json.contains("\"targetWeight\":140000"))
        #expect(json.contains("\"modifiers\":[\"belt\",\"curriculum\"]"))
        #expect(!json.contains("\"grams\""))
        #expect(!json.contains("rawValue"))
    }

    @Test("A vocabulary value is its bare raw spelling")
    func vocabularyValuesAreBare() throws {
        let json = try jsonText(of: codingExercise())

        #expect(json.contains("\"movement\":\"squat\""))
        #expect(json.contains("\"laterality\":\"unilateral\""))
        #expect(json.contains("\"barType\":\"safetySquat\""))
        // `FR-1.7.5`'s override crosses the wire as grams, like every other mass (`G-1.1`).
        #expect(json.contains("\"manualE1RM\":182500"))
    }

    @Test("A profile's inventory stays two positionally paired lists")
    func inventoryStaysTwoLists() throws {
        let json = try jsonText(of: codingEquipmentProfile())

        #expect(json.contains("\"plates\":[25000,15000]"))
        #expect(json.contains("\"platePairCounts\":[2,3]"))
    }

    @Test("A routine target group's weight is a bare integer of grams")
    func targetGroupWeightIsBare() throws {
        let json = try jsonText(of: codingRoutineTargetGroup())

        #expect(json.contains("\"targetWeight\":90000"))
        #expect(!json.contains("\"grams\""))
    }
}

@Suite("Records round-trip through JSON")
struct RecordJSONRoundTripTests {
    // Nine round trips, each anchored on the whole record rather than on a field, so a conformance
    // that dropped a key fails here as well as in the key-spelling suite.

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

@Suite("Decoding costs a field, never the record")
struct RecordDecodingFallbackTests {
    private func decode<R: StoredRecord>(_ type: R.Type, replacing: (String, String), in record: R) throws -> R {
        let json = try jsonText(of: record)
        let mutated = json.replacingOccurrences(of: replacing.0, with: replacing.1)
        return try JSONDecoder().decode(R.self, from: Data(mutated.utf8))
    }

    // The wire half of rule 4, and the reason `RecordVocabulary` is one table read from two places:
    // a row arriving through a backup file has to resolve exactly as the same row arriving through
    // the store. Each case asserts a neighbouring field too — a decoder that threw the record away
    // and rebuilt an empty one would satisfy the fallback assertion alone.
    @Test("An unreadable movement resolves without costing the exercise")
    func unknownMovementResolves() throws {
        let record = try decode(
            Exercise.self,
            replacing: ("\"movement\":\"squat\"", "\"movement\":\"kettlebellSwing\""),
            in: codingExercise())

        #expect(record.movement == .other)
        #expect(record.name == "Low-bar back squat")
    }

    // `Laterality` throws on an unrecognised spelling and `E1RMFormulaID` throws too, so these two
    // are where a decoder that reached for the synthesised conformance would lose the whole record.
    @Test("An unreadable laterality resolves without costing the exercise")
    func unknownLateralityResolves() throws {
        let record = try decode(
            Exercise.self,
            replacing: ("\"laterality\":\"unilateral\"", "\"laterality\":\"contralateral\""),
            in: codingExercise())

        #expect(record.laterality == .bilateral)
        #expect(record.barType == .safetySquat)
    }

    /// Rule 4 over the twelfth vocabulary column: a scope spelling from a newer version costs that
    /// preference and nothing else.
    @Test("An unreadable feed scope resolves without costing the other preferences")
    func unknownScopeResolves() throws {
        let record = try decode(
            UserSettings.self,
            replacing: (
                "\"recentRecordsScope\":\"dashboardLifts\"",
                "\"recentRecordsScope\":\"strongestLifts\""
            ),
            in: codingUserSettings())

        #expect(record.recentRecordsScope == .dashboardLifts)
        #expect(record.theme == .dark)
        #expect(record.displayUnit == .pounds)
    }

    @Test("An unreadable formula name resolves without costing the other preferences")
    func unknownFormulaResolves() throws {
        let record = try decode(
            UserSettings.self,
            replacing: ("\"e1RMFormula\":\"brzycki\"", "\"e1RMFormula\":\"mayhew\""),
            in: codingUserSettings())

        #expect(record.e1RMFormula == .epley)
        #expect(record.theme == .dark)
        #expect(record.displayUnit == .pounds)
    }

    /// `DisplayPrecision` refuses a step below one milli-unit on the way in, and it is right to —
    /// something downstream divides by it. Refusing it *at the record* would cost the theme, the
    /// unit, the rounding defaults and `userID` as well, which is the one thing rule 4 forbids.
    @Test("An unreadable display step costs that preference and nothing else")
    func unreadableDisplayStepResolves() throws {
        var configured = codingUserSettings()
        configured.displayPrecision = .quarter

        let zeroed = try decode(
            UserSettings.self,
            replacing: ("\"displayPrecision\":250", "\"displayPrecision\":0"),
            in: configured)
        let mistyped = try decode(
            UserSettings.self,
            replacing: ("\"displayPrecision\":250", "\"displayPrecision\":\"quarter\""),
            in: configured)

        #expect(zeroed.displayPrecision == nil)
        #expect(mistyped.displayPrecision == nil)
        // The neighbours a decoder that threw the record away could not have kept.
        #expect(zeroed.theme == .dark)
        #expect(zeroed.userID == configured.userID)
        #expect(mistyped.displayUnit == .pounds)
    }

    @Test("An unreadable training-max source resolves without costing the row")
    func unknownTrainingMaxSourceResolves() throws {
        let record = try decode(
            TrainingMaxEntry.self,
            replacing: ("\"source\":\"percentOfRepMax\"", "\"source\":\"percentOfVelocityLoss\""),
            in: codingTrainingMaxEntry())

        #expect(record.source == .manual)
        #expect(record.percentage == 0.85)
    }

    // The exception to the table, and the one that would be silently destroyed by obeying it: a
    // modifier spelling has no other copy anywhere.
    @Test("An unrecognised modifier spelling decodes verbatim")
    func unknownModifierIsPreserved() throws {
        let json = try jsonText(of: codingSetEntry())
        let record = try JSONDecoder().decode(SetEntry.self, from: Data(json.utf8))

        #expect(record.modifiers.map(\.rawValue) == ["belt", "curriculum"])
    }

    // A record validates nothing on decode, unlike `SetRecord`, whose decoder re-runs its ranges.
    // That is the mirror-the-row decision on the wire: a backup that could not carry an RPE of 47
    // could not export the row a repair exists for.
    @Test("An out-of-range RPE decodes rather than throwing")
    func outOfRangeValuesDecode() throws {
        let record = try decode(
            SetEntry.self, replacing: ("\"rpe\":8.5", "\"rpe\":47"), in: codingSetEntry())

        #expect(record.rpe == 47)
    }

    // The one normalisation any record performs has to run here too, or the format admits two
    // encodings of one set — and a decoded record would compare unequal to the same set read from
    // the store. Five spellings rather than two: the mutation worth catching is a decoder that
    // deduplicates without sorting, whose own output order is nondeterministic and passes a
    // two-element assertion about half the time.
    @Test("Decoding canonicalises the modifier list")
    func decodingCanonicalisesModifiers() throws {
        let json = """
            {"id":"0f7b6a5c-1111-4222-8333-444455556666","createdAt":0,"updatedAt":0,
             "entryID":"0f7b6a5c-7777-4888-8999-aaaabbbbcccc","order":0,"weight":100000,"reps":5,
             "isWarmup":false,"isCompleted":true,
             "modifiers":["sleeves","belt","wraps","sleeves","deficit","paused"],"notes":""}
            """
        let record = try JSONDecoder().decode(SetEntry.self, from: Data(json.utf8))

        #expect(record.modifiers.map(\.rawValue) == ["belt", "deficit", "paused", "sleeves", "wraps"])
    }

    // What still throws, and why it is not a contradiction of rule 4: a string where an integer
    // belongs is corruption rather than a newer vocabulary, and a record that invented a value for
    // it would be a backup that cannot be told from a good one.
    @Test("A value of the wrong type still throws")
    func wrongTypedValueThrows() throws {
        let json = try jsonText(of: codingSetEntry())
            .replacingOccurrences(of: "\"reps\":5", with: "\"reps\":\"five\"")

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SetEntry.self, from: Data(json.utf8))
        }
    }
}
