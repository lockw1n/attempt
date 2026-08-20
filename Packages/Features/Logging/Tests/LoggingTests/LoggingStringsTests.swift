import Foundation
import Testing

@testable import Logging

/// `G-3.4`: this module's copy is in its own catalogue and reaches the screen from there. The shape
/// is `SettingsStrings`' test, including the reason each assertion exists — that file is where the
/// argument lives.
@Suite("Logging copy")
struct LoggingStringsTests {
    @Test("Every key the screens can show resolves to real copy")
    func everyKeyResolves() {
        #expect(!LoggingStrings.all.isEmpty)
        for resource in LoggingStrings.all {
            let rendered = String(localized: resource)
            #expect(rendered != resource.key, "unresolved key \(resource.key)")
            #expect(!rendered.isEmpty)
        }
    }

    @Test("The catalogue is this module's, not the app's")
    func copyComesFromTheModuleBundle() {
        #expect(Bundle.module.localizations == ["en"])
        #expect(String(localized: LoggingStrings.trainStartAction) == "Start workout")
    }

    @Test("The catalogue and the accessors name exactly the same keys")
    func catalogueAndAccessorsAgree() throws {
        let url = try #require(
            Bundle.module.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: "en"
            ))
        let catalogue = try #require(NSDictionary(contentsOf: url) as? [String: String])
        #expect(Set(catalogue.keys) == Set(LoggingStrings.all.map(\.key)))
        #expect(!catalogue.isEmpty)
    }

    @Test("Keys follow the convention: lowercase, dotted, module-prefixed")
    func keysFollowTheConvention() {
        for resource in LoggingStrings.all {
            let key = resource.key
            #expect(key.hasPrefix("logging."), "\(key) does not name its module")
            #expect(key.split(separator: ".").count >= 3, "\(key) is too shallow")
            #expect(key == key.lowercased(), "\(key) is not lowercase")
        }
    }
}
