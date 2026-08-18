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
        #expect(Bundle.module.localizations == ["en"])
        #expect(String(localized: SettingsStrings.unitsTitle) == "Units")
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
        let url = try #require(
            Bundle.module.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: "en"
            ))
        // `NSDictionary` reads both forms this file takes: the text `.strings` SwiftPM copies, and
        // the binary plist `xcodebuild` compiles it to.
        let catalogue = try #require(NSDictionary(contentsOf: url) as? [String: String])
        #expect(Set(catalogue.keys) == Set(SettingsStrings.all.map(\.key)))
        #expect(!catalogue.isEmpty)
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
}
