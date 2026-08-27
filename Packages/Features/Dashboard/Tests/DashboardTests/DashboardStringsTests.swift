import Foundation
import Testing

@testable import Dashboard

/// `G-3.4`: this module's copy is in its own catalogue and reaches the screen from there. The shape
/// is `ExerciseLibraryStringsTests`', including why each assertion exists.
@Suite("Dashboard copy")
struct DashboardStringsTests {
    @Test("Every key the screen can show resolves to real copy")
    func everyKeyResolves() {
        #expect(!DashboardStrings.all.isEmpty)
        for resource in DashboardStrings.all {
            let rendered = String(localized: resource)
            #expect(rendered != resource.key, "unresolved key \(resource.key)")
            #expect(!rendered.isEmpty)
        }
    }

    @Test("The catalogue is this module's, not the app's")
    func copyComesFromTheModuleBundle() {
        #expect(Bundle.module.localizations == ["en"])
        #expect(String(localized: DashboardStrings.recentRecordsTitle) == "Recent PRs")
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
        #expect(Set(catalogue.keys) == Set(DashboardStrings.all.map(\.key)))
        #expect(!catalogue.isEmpty)
    }

    @Test("Keys follow the convention: lowercase, dotted, module-prefixed")
    func keysFollowTheConvention() {
        for resource in DashboardStrings.all {
            let key = resource.key
            #expect(key.hasPrefix("dashboard."), "\(key) does not name its module")
            #expect(key.split(separator: ".").count >= 3, "\(key) is too shallow")
            #expect(key == key.lowercased(), "\(key) is not lowercase")
        }
    }

    /// The two forms are one label at two shapes, and the range one has to keep both numbers — a
    /// translation that dropped one would read as the wrong record.
    @Test("A single N and a span read as different labels")
    func theTwoRepMaxFormsDiffer() {
        #expect(String(localized: DashboardStrings.recentRecordsRepMax(3)) == "3-rep max")
        #expect(String(localized: DashboardStrings.recentRecordsRepMaxRange(1, 3)) == "1–3-rep max")
    }
}
