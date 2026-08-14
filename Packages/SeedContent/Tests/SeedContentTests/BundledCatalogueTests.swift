import Foundation
import SeedContent
import Testing

// TR-0.5.1 and FR-1.1.7. The shipped catalogue is checked by the same validator that gates any
// other payload — there is no second set of rules for the copy we author ourselves. What the
// validator cannot check is pinned here instead: it knows an id is well-formed and unique, not that
// it is the one we published, and it knows `implementCount` is positive when present, not that the
// entries needing it still say so.

/// A catalogue entry a test names by its permanent id.
///
/// The id stays a `String` and is parsed at the point of use, so a literal that does not parse
/// fails as a malformed literal rather than as a catalogue entry that has gone missing.
struct NamedExercise: Sendable, CustomTestStringConvertible {
    let name: String
    let rawID: String

    var testDescription: String { name }

    init(_ name: String, _ rawID: String) {
        self.name = name
        self.rawID = rawID
    }
}

/// The five lifts the catalogue is organised around, walked rather than named one test each.
let primaryLifts: [NamedExercise] = [
    // The three competition lifts.
    NamedExercise("Back Squat", "61b1f9fd-7f08-4ca8-961b-533acd8d764d"),
    NamedExercise("Bench Press", "320c0012-d049-49ef-adfa-c2625156afe4"),
    NamedExercise("Deadlift", "9b9240e4-0a21-4a42-a251-63d9a6fa3186"),
    NamedExercise("Overhead Press", "d16bafa2-ab7a-464b-8892-a6584b33eafa"),
    NamedExercise("Barbell Row", "ad89efd2-d38c-46e7-8d99-8ac8f3b35160"),
]

/// Every entry one rep of which loads a pair of implements.
///
/// **Walked rather than spot-checked, and complete rather than a sample.** `implementCount` is
/// optional with an implied one, so an entry that loses the key still validates and still decodes —
/// it just halves that exercise's tonnage for good. Nothing else in the suite notices.
let pairLoadedExercises: [NamedExercise] = [
    NamedExercise("Bulgarian Split Squat", "33b1ddc7-efbe-478e-b09c-8a547417ba25"),
    NamedExercise("Walking Lunge", "4ec70408-8fb9-4b58-954c-e21a60b056ab"),
    NamedExercise("Reverse Lunge", "78de87db-c8da-4403-af62-cc9292f9fd26"),
    NamedExercise("Step-Up", "dc0ae6db-0d4f-424a-8093-f81749d732bc"),
    NamedExercise("Dumbbell Bench Press", "d1a95f54-3cc7-4102-a525-76aa905fe513"),
    NamedExercise("Incline Dumbbell Press", "0f08d182-c3c9-4de5-a166-8284d28da6b3"),
    NamedExercise("Dumbbell Romanian Deadlift", "bd39b577-048d-4712-8dba-971184056873"),
    NamedExercise("Single-Leg Romanian Deadlift", "ac17aec3-dddc-4bd2-9e32-cb7d8d8cb008"),
    NamedExercise("Dumbbell Shoulder Press", "401c946b-114e-4389-82f8-d6e23c257d23"),
    NamedExercise("Seated Dumbbell Shoulder Press", "a0a70984-24ec-4678-8a94-a77afec92d02"),
    NamedExercise("Arnold Press", "f932fe97-9649-4789-8d80-a0371e70447b"),
    NamedExercise("Two-Dumbbell Row", "f5862315-770f-4415-aac7-f7f3998f5568"),
    NamedExercise("Dumbbell Curl", "a6332b21-a1f0-41f2-b086-99e2cf698b9b"),
    NamedExercise("Hammer Curl", "9aebe453-3fee-4426-9cec-07bb76b981cc"),
    NamedExercise("Lateral Raise", "bf32da3e-fdf7-4975-9c40-2001597ead92"),
    NamedExercise("Rear Delt Fly", "9c36b585-d4d5-4cce-b144-41a64f93d26d"),
    NamedExercise("Dumbbell Chest Fly", "6782cc86-b33c-484a-89db-fbc08a58c5ed"),
    NamedExercise("Dumbbell Shrug", "a0b3b8a9-102d-443a-b1aa-5ba52647edf9"),
    NamedExercise("Farmer's Walk", "ea9ee911-8db3-42be-b6fe-754dad6f5ed3"),
]

/// FNV-1a over every id in sorted order, which is what lets one literal stand for a hundred-odd
/// permanent values. Hand-rolled rather than imported so the digest does not depend on a platform's
/// hashing being stable between releases.
func idDigest(_ ids: [UUID]) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in ids.map(\.uuidString).sorted().joined(separator: "\n").utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
    }
    return hash
}

@Suite("Bundled exercise catalogue")
struct BundledCatalogueTests {
    private func decoded() throws -> SeedCatalogue {
        try JSONDecoder().decode(SeedCatalogue.self, from: BundledCatalogue.data())
    }

    private func id(of exercise: NamedExercise) throws -> UUID {
        try #require(UUID(uuidString: exercise.rawID), "\(exercise.name) has a malformed id literal")
    }

    // The floor is written out rather than read from `minimumExercises`, so weakening the shipped
    // constant cannot weaken this test. The next test is what ties the two together.
    @Test("The shipped catalogue passes the validator at TR-0.5.1's floor")
    func shippedCatalogueValidates() throws {
        let failures = SeedCatalogueValidator.validate(
            try BundledCatalogue.data(), minimumExercises: 80)

        #expect(failures.map(\.description) == [])
    }

    @Test("The floor the package publishes is the one TR-0.5.1 states")
    func publishedMinimumIsTheRequirementsFloor() {
        #expect(BundledCatalogue.minimumExercises == 80)
    }

    // Presence, name and variation count in one walk: a lift the file no longer carries under that
    // id fails at the `#require` before the count is reached.
    @Test(
        "Each primary lift is present under its published id, with variations to display",
        arguments: primaryLifts)
    func primaryLiftHasVariations(_ lift: NamedExercise) throws {
        let liftID = try id(of: lift)
        let catalogue = try decoded()
        let root = try #require(catalogue.exercises.first { $0.id == liftID })
        let variations = catalogue.exercises.filter { $0.parentExerciseID == liftID }

        #expect(root.name == lift.name)
        #expect(root.parentExerciseID == nil)
        #expect(variations.count >= 3)
    }

    /// Ids are permanent, and the validator can tell that they are well-formed and unique but not
    /// that they are the *same* ones as last release. The literals above catch a bulk re-mint; this
    /// catches the single-entry one, which is the likelier accident.
    ///
    /// **Adding an entry moves both numbers below, and that is expected.** Update them from the
    /// failure, then read the diff and confirm no line but the new one moved.
    @Test("Every id is the one it was published with")
    func publishedIDsAreUnchanged() throws {
        let ids = try decoded().exercises.map(\.id)

        #expect(ids.count == 116)
        #expect(idDigest(ids) == 0x2452_4158_c12f_3ec8)
    }

    @Test("Each pair-loaded entry still says so", arguments: pairLoadedExercises)
    func pairLoadedEntryCarriesTwo(_ exercise: NamedExercise) throws {
        let entryID = try id(of: exercise)
        let entry = try #require(try decoded().exercises.first { $0.id == entryID })

        #expect(entry.name == exercise.name)
        #expect(entry.implementCount == 2)
    }

    // The other half of the rule: the list above is exhaustive, so a count appearing anywhere else
    // is an authoring slip rather than a new pair. `implementCount` is never authored as `1` —
    // absent is how one implement is spelled, and the two stay distinguishable on the wire.
    @Test("No entry outside that list claims a count at all")
    func onlyTheListedEntriesCarryACount() throws {
        let listed = Set(pairLoadedExercises.compactMap { UUID(uuidString: $0.rawID) })
        let unexpected = try decoded().exercises
            .filter { !listed.contains($0.id) && $0.implementCount != nil }

        // A literal that failed to parse would drop out of `listed` and make this pass vacuously.
        #expect(listed.count == 19)
        #expect(unexpected.map(\.name) == [])
    }
}
