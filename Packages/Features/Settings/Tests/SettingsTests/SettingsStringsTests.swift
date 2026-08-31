import Foundation
import PowerliftingCore
import Testing

@testable import Settings

/// `G-3.4`: this module's copy is in its own catalogue, and reaches the screen from there.
@Suite("Settings copy")
struct SettingsStringsTests {
    @Test("Every key the screen can show resolves to real copy")
    func everyKeyResolves() {
        // A loop over an empty collection passes every assertion in it, which is how an `all` that
        // stopped listing its keys would read as green. The count it is held to is the catalogue's
        // own, asserted below — a literal here would have to be edited by the same hand that
        // forgot the key.
        #expect(!SettingsStrings.all.isEmpty)
        for resource in SettingsStrings.all {
            let rendered = String(localized: resource)
            // A key with no entry resolves to itself — measured, and it is the only failure this
            // catalogue has: a missing key is silent everywhere else.
            #expect(rendered != resource.key, "unresolved key \(resource.key)")
            #expect(!rendered.isEmpty)
        }
    }

    @Test("The catalogue is this module's, not the app's")
    func copyComesFromTheModuleBundle() {
        #expect(Bundle.module.localizations.sorted() == ["en", "uk"])
        #expect(String(localized: SettingsStrings.unitsTitle) == "Units")
    }

    /// `FR-1.14.1`. `scripts/check-translations.sh` is what holds the whole table complete, key for
    /// key; what it cannot say is that the table reached the built bundle, which is the half a
    /// comparison of two files in the repo has no way to see.
    @Test("The Ukrainian catalogue is in this module's bundle")
    func ukrainianCopyIsBundled() throws {
        let url = try #require(
            Bundle.module.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: "uk"
            ))
        let catalogue = try #require(NSDictionary(contentsOf: url) as? [String: String])
        #expect(catalogue["settings.landing.units.title"] == "Одиниці")
    }

    @Test("Both display units have an abbreviation, and they differ")
    func unitSymbolsAreDistinct() {
        let symbols = MassUnit.allCases.map { String(localized: SettingsStrings.unitSymbol(for: $0)) }
        #expect(symbols == ["kg", "lb"])
    }

    /// The accessors and the catalogue are two hand-maintained lists, and the count anchor this
    /// replaced only caught one of the two ways they drift. A key added to the catalogue and to the
    /// screen but never appended to `all` left the count at 10 and went untested; an orphan key
    /// nothing reads was invisible in the other direction. Set equality catches both.
    @Test("The catalogue and the accessors name exactly the same keys")
    func catalogueAndAccessorsAgree() throws {
        // Two files, one catalogue: `FR-1.7.1`'s lookback is a count of days and so a plural, which
        // only the `.stringsdict` can express, and a key in one file must not also be in the other.
        let strings = try Self.keys(inCatalogueNamed: "strings")
        let plurals = try Self.keys(inCatalogueNamed: "stringsdict")
        #expect(strings.isDisjoint(with: plurals))
        #expect(strings.union(plurals) == Set(SettingsStrings.all.map(\.key)))
        #expect(!strings.isEmpty)
        #expect(!plurals.isEmpty)
    }

    @Test("The lookback window pluralises on the number of days")
    func lookbackPluralises() {
        // The picker offers whatever is in force, including a one-day window carried in by a
        // restore, which a `.strings` format would render "1 days" (`G-3.4`).
        #expect(String(localized: SettingsStrings.lookbackDays(1)) == "1 day")
        #expect(String(localized: SettingsStrings.lookbackDays(90)) == "90 days")
        #expect(String(localized: SettingsStrings.lookbackDays(0)) == "0 days")
    }

    @Test("Keys follow the convention: lowercase, dotted, module-prefixed")
    func keysFollowTheConvention() {
        for resource in SettingsStrings.all {
            let key = resource.key
            #expect(key.hasPrefix("settings."), "\(key) does not name its module")
            #expect(key.split(separator: ".").count >= 3, "\(key) is too shallow")
            #expect(key == key.lowercased(), "\(key) is not lowercase")
        }
    }

    /// Every key in one of this module's two catalogue files.
    ///
    /// `NSDictionary` reads both forms each file takes: the text SwiftPM copies, and the binary
    /// plist `xcodebuild` compiles it to.
    ///
    /// - Parameter ext: `strings` or `stringsdict`.
    /// - Returns: The keys it declares.
    private static func keys(inCatalogueNamed ext: String) throws -> Set<String> {
        let url = try #require(
            Bundle.module.url(
                forResource: "Localizable",
                withExtension: ext,
                subdirectory: nil,
                localization: "en"
            ))
        return Set(try #require(NSDictionary(contentsOf: url) as? [String: Any]).keys)
    }
}
