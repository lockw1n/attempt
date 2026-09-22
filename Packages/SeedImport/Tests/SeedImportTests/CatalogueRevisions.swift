import Foundation
import SeedContent
import Testing

/// The bytes of a fixture file.
///
/// **`FileManager.contents(atPath:)` rather than `Data(contentsOf:)`**, which
/// `no_networking_in_seed_import` refuses anywhere under this package — a `URL` initialiser takes a
/// scheme of any kind and blocks on an http one. Reading by path cannot reach the network at all,
/// which is the rule's point rather than a way around it.
func fixture(_ name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
        "no fixture named \(name).json")
    return try #require(
        FileManager.default.contents(atPath: url.path), "\(name).json could not be read")
}

/// `DOD-18.5`'s pair: the catalogue as it shipped at revision 3, and the revision that corrects one
/// Ukrainian name (`FR-18.2.2`).
///
/// **Revision 3 is a frozen copy rather than the shipped file.** `T-18.05` is about to rewrite the
/// real catalogue, and a fixture that moves with its subject cannot say what an import did to a
/// store seeded by an older revision.
///
/// **Revision 4 is derived from it by text rather than committed beside it.** A second 35 kB copy
/// would be two files to keep in step for one changed entry, and the interesting property — that
/// everything except one name is byte-identical — is exactly what the derivation states. Both edits
/// are required to apply, so a fixture reshaped under this loader fails here rather than passing
/// vacuously somewhere downstream.
struct CatalogueRevisions {
    /// The Ukrainian name `FR-18.2.2` retires: nobody is *в нахилі* on a reverse pec deck.
    static let retiredRearDeltName = "Махи в тренажері в нахилі"

    /// What it becomes, pairing with *Зведення рук у тренажері* (Machine Chest Fly).
    static let correctedRearDeltName = "Розведення рук у тренажері"

    /// The catalogue as committed today.
    let three: Data

    /// The same catalogue with one entry's Ukrainian name corrected and the retired one listed.
    let four: Data

    /// The entry the correction is about.
    let rearDeltFlyID: UUID

    /// A second built-in, so a test has a row to rename by hand and watch survive.
    let backSquatID: UUID

    init() throws {
        three = try fixture("catalogue-revision-3")
        let text = try #require(String(data: three, encoding: .utf8), "revision 3 is not UTF-8")

        let retired = "\"ukrainianName\": \"\(Self.retiredRearDeltName)\""
        let corrected =
            "\"ukrainianName\": \"\(Self.correctedRearDeltName)\", "
            + "\"formerUkrainianNames\": [\"\(Self.retiredRearDeltName)\"]"
        try #require(text.contains(retired), "revision 3 no longer carries the retired name")
        try #require(text.contains("\"revision\": 3"), "the frozen fixture is no longer revision 3")

        four = Data(
            text
                .replacingOccurrences(of: retired, with: corrected)
                .replacingOccurrences(of: "\"revision\": 3", with: "\"revision\": 4")
                .utf8)

        let entries = try JSONDecoder().decode(SeedCatalogue.self, from: three).exercises
        rearDeltFlyID = try #require(
            entries.first { $0.ukrainianName == Self.retiredRearDeltName }?.id,
            "revision 3 has no entry carrying the retired name")
        backSquatID = try #require(
            entries.first { $0.name == "Back Squat" }?.id, "revision 3 has no Back Squat")
    }
}
