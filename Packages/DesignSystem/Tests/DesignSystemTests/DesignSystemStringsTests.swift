import Foundation
import Testing

@testable import DesignSystem

/// `G-3.4`: the copy this module owns is in its own catalogue, and reaches the screen from there.
///
/// The module owns copy at all only because the five state placeholders do — see
/// ``DesignSystemStrings`` for where the line between the caller's copy and this module's runs.
@Suite("Design system copy")
struct DesignSystemStringsTests {
    @Test("Every key a state placeholder can show resolves to real copy")
    func everyKeyResolves() {
        // A loop over an empty collection passes every assertion in it, which is how an `all` that
        // stopped listing its keys would read as green.
        #expect(!DesignSystemStrings.all.isEmpty)
        for resource in DesignSystemStrings.all {
            let rendered = String(localized: resource)
            // A key with no entry resolves to itself, which is the only failure this catalogue has:
            // a missing key is silent everywhere else.
            #expect(rendered != resource.key, "unresolved key \(resource.key)")
            #expect(!rendered.isEmpty)
        }
    }

    @Test("The catalogue is this module's, not the app's")
    func copyComesFromTheModuleBundle() {
        #expect(Bundle.module.localizations == ["en"])
        #expect(String(localized: DesignSystemStrings.retry) == "Try again")
    }

    /// The accessors and the catalogue are two hand-maintained lists and they drift in two
    /// directions: a key added to the catalogue and to a view but never appended to `all` is
    /// untested, and an orphan key nothing reads is invisible. Set equality catches both.
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
        #expect(Set(catalogue.keys) == Set(DesignSystemStrings.all.map(\.key)))
        #expect(!catalogue.isEmpty)
    }

    @Test("Keys follow the convention: lowercase, dotted, module-prefixed")
    func keysFollowTheConvention() {
        for resource in DesignSystemStrings.all {
            let key = resource.key
            #expect(key.hasPrefix("designsystem."), "\(key) does not name its module")
            #expect(key.split(separator: ".").count >= 3, "\(key) is too shallow")
            #expect(key == key.lowercased(), "\(key) is not lowercase")
        }
    }

    /// `G-2.1` is the requirement the offline copy exists to keep: every action still works
    /// offline, so the state must not read as "your training log is gone". The claim is about a
    /// sentence, so it is pinned to the sentence rather than to a word — an edit that drops the
    /// reassurance is exactly the edit this catches.
    @Test("The offline message says the logged work is unaffected")
    func offlineMessageReassures() {
        let message = String(localized: DesignSystemStrings.offlineMessage)
        #expect(message.contains("on this device"))
        #expect(message.contains("still works"))
    }
}
