import Foundation
import SeedContent
import Testing

// TR-0.5.1 and FR-1.1.7. The shipped catalogue is checked by the same validator that gates any
// other payload — there is no second set of rules for the copy we author ourselves.

/// A lift whose variations `FR-1.1.7`'s parent → variations view exists to display, named by its
/// permanent id.
struct PrimaryLift: Sendable, CustomTestStringConvertible {
    let name: String
    let id: UUID

    var testDescription: String { name }

    init(_ name: String, _ id: String) {
        self.name = name
        self.id = UUID(uuidString: id) ?? UUID()
    }
}

/// The five lifts the catalogue is organised around, walked rather than named one test each.
///
/// **The literals are the regeneration guard.** Ids are permanent, so re-minting the catalogue's
/// fails all five of these at once — which is the only cheap way to notice, since the validator can
/// tell that ids are well-formed and unique but not that they are the *same* ones as last release.
let primaryLifts: [PrimaryLift] = [
    // The three competition lifts.
    PrimaryLift("Back Squat", "61b1f9fd-7f08-4ca8-961b-533acd8d764d"),
    PrimaryLift("Bench Press", "320c0012-d049-49ef-adfa-c2625156afe4"),
    PrimaryLift("Deadlift", "9b9240e4-0a21-4a42-a251-63d9a6fa3186"),
    PrimaryLift("Overhead Press", "d16bafa2-ab7a-464b-8892-a6584b33eafa"),
    PrimaryLift("Barbell Row", "ad89efd2-d38c-46e7-8d99-8ac8f3b35160"),
]

@Suite("Bundled exercise catalogue")
struct BundledCatalogueTests {
    private func decoded() throws -> SeedCatalogue {
        try JSONDecoder().decode(SeedCatalogue.self, from: BundledCatalogue.data())
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
    func primaryLiftHasVariations(_ lift: PrimaryLift) throws {
        let catalogue = try decoded()
        let root = try #require(catalogue.exercises.first { $0.id == lift.id })
        let variations = catalogue.exercises.filter { $0.parentExerciseID == lift.id }

        #expect(root.name == lift.name)
        #expect(root.parentExerciseID == nil)
        #expect(variations.count >= 3)
    }
}
