import Foundation
import Testing

@testable import History

/// `G-3.4`: this module's copy is in its own catalogue and reaches the screen from there. The shape
/// is `LoggingStringsTests`', including the reason each assertion exists.
@Suite("History copy")
struct HistoryStringsTests {
    @Test("Every key the screen can show resolves to real copy")
    func everyKeyResolves() {
        #expect(!HistoryStrings.all.isEmpty)
        for resource in HistoryStrings.all {
            let rendered = String(localized: resource)
            #expect(rendered != resource.key, "unresolved key \(resource.key)")
            #expect(!rendered.isEmpty)
        }
    }

    @Test("The catalogue is this module's, not the app's")
    func copyComesFromTheModuleBundle() {
        #expect(Bundle.module.localizations.sorted() == ["en", "uk"])
        #expect(String(localized: HistoryStrings.emptyHeadline) == "No training logged yet")
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
        #expect(catalogue["history.list.empty.action"] == "Почати тренування")
    }

    @Test("The catalogue and the accessors name exactly the same keys")
    func catalogueAndAccessorsAgree() throws {
        // Two files, one catalogue: the row's accessibility sentence is a plural, which only the
        // `.stringsdict` can express, and a key in one file must not also be in the other.
        let strings = try Self.keys(inCatalogueNamed: "strings")
        let plurals = try Self.keys(inCatalogueNamed: "stringsdict")
        #expect(strings.isDisjoint(with: plurals))
        #expect(strings.union(plurals) == Set(HistoryStrings.all.map(\.key)))
        #expect(!strings.isEmpty)
        #expect(!plurals.isEmpty)
    }

    @Test("The row's summary pluralises on the set count")
    func metricsSummaryPluralises() {
        // A session with one working set in it would otherwise read "1 working sets" — on screen
        // and to VoiceOver, since this line is both — and a `.strings` format cannot fix it
        // (`G-3.4`, `G-4.2`).
        #expect(
            String(localized: HistoryStrings.metricsSummary(sets: 1, volume: "100 kg"))
                == "1 working set, 100 kg")
        #expect(
            String(localized: HistoryStrings.metricsSummary(sets: 12, volume: "5,400 kg"))
                == "12 working sets, 5,400 kg")
        #expect(
            String(localized: HistoryStrings.metricsSummary(sets: 0, volume: "0 kg"))
                == "0 working sets, 0 kg")
    }

    @Test("Keys follow the convention: lowercase, dotted, module-prefixed")
    func keysFollowTheConvention() {
        for resource in HistoryStrings.all {
            let key = resource.key
            #expect(key.hasPrefix("history."), "\(key) does not name its module")
            #expect(key.split(separator: ".").count >= 3, "\(key) is too shallow")
            #expect(key == key.lowercased(), "\(key) is not lowercase")
        }
    }

    /// Every key in one of this module's two catalogue files.
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
