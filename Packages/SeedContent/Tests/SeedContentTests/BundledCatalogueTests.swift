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
    NamedExercise("Seated Dumbbell Shrug", "5b5c3401-16da-40b0-9335-f6d446182204"),
    NamedExercise("Farmer's Walk", "ea9ee911-8db3-42be-b6fe-754dad6f5ed3"),
]

/// A variation and the exercise it varies (`FR-1.1.7`).
///
/// Named rather than keyed on ids: the validator refuses a parent no entry carries, so what is left
/// to get wrong is a parent that resolves — to the wrong exercise. These are the edges where the
/// family an entry belongs to is a judgement rather than a spelling.
struct VariationEdge: Sendable, CustomTestStringConvertible {
    let child: String
    let parent: String

    var testDescription: String { "\(child) varies \(parent)" }

    init(_ child: String, _ parent: String) {
        self.child = child
        self.parent = parent
    }
}

let variationEdges: [VariationEdge] = [
    VariationEdge("Lever Chest Press", "Machine Chest Press"),
    VariationEdge("Incline Lever Chest Press", "Machine Chest Press"),
    VariationEdge("Independent-Arm Machine Chest Press", "Machine Chest Press"),
    VariationEdge("Lever Shoulder Press", "Machine Shoulder Press"),
    VariationEdge("Lever High Row", "Chest-Supported Machine Row"),
    VariationEdge("Close-Grip Lat Pulldown", "Lat Pulldown"),
    VariationEdge("Wide-Grip Lat Pulldown", "Lat Pulldown"),
    VariationEdge("Rope Triceps Pushdown", "Triceps Pushdown"),
    VariationEdge("Machine Lateral Raise", "Lateral Raise"),
    VariationEdge("Machine Rear Delt Fly", "Rear Delt Fly"),
    VariationEdge("Seated Dumbbell Shrug", "Dumbbell Shrug"),
    VariationEdge("Seated Leg Curl", "Leg Curl"),
    VariationEdge("Lying Leg Curl", "Leg Curl"),
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

        #expect(ids.count == 132)
        #expect(idDigest(ids) == 0xb689_c4aa_cc95_2774)
    }

    // FR-1.14.2's catalogue half, over the file we actually ship. `SeedUkrainianNameTests` proves the
    // key decodes; these prove it is authored on every entry, which nothing at runtime would report:
    // `displayName(in:)` falls back to the English name, so a translation left out looks to a
    // Ukrainian reader exactly like an exercise nobody has translated yet.
    @Test("Every shipped entry carries a Ukrainian name")
    func everyEntryIsTranslated() throws {
        let untranslated = try decoded().exercises.filter {
            ($0.ukrainianName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        #expect(untranslated.map(\.name) == [])
    }

    // The other half of "authored": a field filled with the English name, or with a transliteration
    // that never reached Cyrillic, satisfies the test above and reads as a translation to every
    // caller. A bar or machine whose name is an **acronym** keeps it — `EZ`, `SSB`, `GHD` — while a
    // descriptive one is described (`Swiss` → швейцарський, `Cambered` → вигнутий), so the rule is
    // "contains Cyrillic", not "is Cyrillic throughout".
    //
    // A missing or blank field is `everyEntryIsTranslated`'s to report and is skipped here: it
    // contains no Cyrillic either, so without the skip that test could not fail alone and its
    // failure would always arrive as two.
    @Test("No shipped translation is the English name, or Latin throughout")
    func translationsAreUkrainian() throws {
        let suspect = try decoded().exercises.filter { entry in
            let ukrainian = (entry.ukrainianName ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ukrainian.isEmpty else { return false }
            let cyrillic = ukrainian.unicodeScalars.contains { (0x0400...0x04ff).contains($0.value) }
            return !cyrillic || ukrainian == entry.name
        }

        #expect(suspect.map(\.name) == [])
    }

    // English names are unique by authoring, and the Ukrainian column has to stay so for the same
    // reason: two rows reading alike in a picker are two rows the lifter cannot choose between, and
    // the likeliest way to get there is a copy-paste while translating a family of variations.
    @Test("No two entries share a Ukrainian name")
    func translationsAreDistinct() throws {
        let catalogue = try decoded()
        let translations = catalogue.exercises.compactMap(\.ukrainianName)
        var seen: Set<String> = []
        let repeated = translations.filter { !seen.insert($0).inserted }

        // Vacuous if the column were empty, which the entry count rules out — read against
        // `everyEntryIsTranslated`, which is what forbids a blank one. Derived rather than written
        // out so that adding an entry moves the two literals in `publishedIDsAreUnchanged` and no
        // third one somewhere else.
        #expect(translations.count == catalogue.exercises.count)
        #expect(repeated == [])
    }

    /// The one entry with that name, refusing both none and several.
    ///
    /// English names are unique by authoring and nothing else checks it, so a duplicate fails here
    /// as a lookup rather than silently picking a winner.
    private func entry(named name: String, in catalogue: SeedCatalogue) throws -> SeedExercise {
        let found = catalogue.exercises.filter { $0.name == name }
        return try #require(found.count == 1 ? found.first : nil, "\(name) is not exactly one entry")
    }

    // The failure this catches is a parent copied from the entry above the intended one: well
    // formed, unique, resolving, and wrong. Both ends are looked up by the name a reader sees.
    @Test("Each variation hangs on the exercise it varies", arguments: variationEdges)
    func variationHangsOnItsParent(_ edge: VariationEdge) throws {
        let catalogue = try decoded()
        let child = try entry(named: edge.child, in: catalogue)
        let parent = try entry(named: edge.parent, in: catalogue)

        #expect(child.parentExerciseID == parent.id)
    }

    // `FR-1.1.7`'s list is every row naming this one as its parent, and it stops there: the
    // detail screen filters on one level. A grandchild would be reachable from nowhere but its own
    // parent's screen, so the catalogue is one level deep and this is what holds it there.
    @Test("No variation hangs on another variation")
    func variationsAreOneLevelDeep() throws {
        let catalogue = try decoded()
        let byID = Dictionary(catalogue.exercises.map { ($0.id, $0) }) { first, _ in first }
        let nested = catalogue.exercises.filter { entry in
            guard let parent = entry.parentExerciseID else { return false }
            return byID[parent]?.parentExerciseID != nil
        }

        // A catalogue of roots would satisfy the filter without exercising it.
        #expect(catalogue.exercises.contains { $0.parentExerciseID != nil })
        #expect(nested.map(\.name) == [])
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
        #expect(listed.count == 20)
        #expect(unexpected.map(\.name) == [])
    }
}
