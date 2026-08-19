import Foundation
import PowerliftingCore
import Testing

@testable import ExerciseLibrary

/// `G-3.4`: this module's copy is in its own catalogue and reaches the screen from there. The shape
/// is `SettingsStrings`' test, including the reason each assertion exists — that file is where the
/// argument lives.
@Suite("Exercise library copy")
struct ExerciseLibraryStringsTests {
    @Test("Every key the screen can show resolves to real copy")
    func everyKeyResolves() {
        #expect(!ExerciseLibraryStrings.all.isEmpty)
        for resource in ExerciseLibraryStrings.all {
            let rendered = String(localized: resource)
            #expect(rendered != resource.key, "unresolved key \(resource.key)")
            #expect(!rendered.isEmpty)
        }
    }

    @Test("The catalogue is this module's, not the app's")
    func copyComesFromTheModuleBundle() {
        #expect(Bundle.module.localizations == ["en"])
        #expect(String(localized: ExerciseLibraryStrings.searchPrompt) == "Search exercises")
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
        #expect(Set(catalogue.keys) == Set(ExerciseLibraryStrings.all.map(\.key)))
        #expect(!catalogue.isEmpty)
    }

    @Test("Keys follow the convention: lowercase, dotted, module-prefixed")
    func keysFollowTheConvention() {
        for resource in ExerciseLibraryStrings.all {
            let key = resource.key
            #expect(key.hasPrefix("exerciselibrary."), "\(key) does not name its module")
            #expect(key.split(separator: ".").count >= 3, "\(key) is too shallow")
            #expect(key == key.lowercased(), "\(key) is not lowercase")
        }
    }

    /// Every movement and every equipment has a label, and no two share one. A vocabulary case added
    /// later reaches this test through `allCases` — which is why the accessors map rather than list.
    @Test("Each vocabulary case has its own label")
    func vocabularyLabelsAreDistinct() {
        let movements = Movement.allCases.map { String(localized: ExerciseLibraryStrings.label(for: $0)) }
        #expect(movements == ["Squat", "Bench", "Deadlift", "Overhead press", "Row", "Other"])

        let equipment = Equipment.allCases.map { String(localized: ExerciseLibraryStrings.label(for: $0)) }
        #expect(Set(equipment).count == Equipment.allCases.count)
        #expect(equipment.first == "Barbell")
    }
}
