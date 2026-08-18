import Foundation
import PowerliftingCore
import Testing

@testable import Settings

/// `G-3.4`: this module's copy is in its own catalogue, and reaches the screen from there.
@Suite("Settings copy")
struct SettingsStringsTests {
    @Test("Every key the screen can show resolves to real copy")
    func everyKeyResolves() {
        // Anchored to a count: a loop over an empty collection passes every assertion in it, which
        // is how a `all` that stopped listing its keys would read as green.
        #expect(SettingsStrings.all.count == 10)
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
