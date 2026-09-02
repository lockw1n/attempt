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
        #expect(Bundle.module.localizations.sorted() == ["en", "uk"])
        #expect(String(localized: LoggingStrings.trainStartAction) == "Start workout")
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
        #expect(catalogue["logging.train.start.action"] == "Почати тренування")
    }

    @Test("The catalogue and the accessors name exactly the same keys")
    func catalogueAndAccessorsAgree() throws {
        // Two files, one catalogue: `FR-1.2.13`'s progress line is a plural, which only the
        // `.stringsdict` can express, and a key in one file must not also be in the other.
        let strings = try Self.keys(inCatalogueNamed: "strings")
        let plurals = try Self.keys(inCatalogueNamed: "stringsdict")
        #expect(strings.isDisjoint(with: plurals))
        #expect(strings.union(plurals) == Set(LoggingStrings.all.map(\.key)))
        #expect(!strings.isEmpty)
        #expect(!plurals.isEmpty)
    }

    @Test("The progress line pluralises on the total, which is the noun's number")
    func progressPluralisesOnTheTotal() {
        // The reason the `.stringsdict` exists. A one-exercise workout is the common case this
        // would otherwise read "1 of 1 exercises complete" in, and a `.strings` format cannot fix
        // it — the count is not the number the noun agrees with (`G-3.4`).
        #expect(
            String(localized: LoggingStrings.sessionProgress(completed: 1, total: 1))
                == "1 of 1 exercise complete")
        #expect(
            String(localized: LoggingStrings.sessionProgress(completed: 3, total: 6))
                == "3 of 6 exercises complete")
        #expect(
            String(localized: LoggingStrings.sessionProgress(completed: 0, total: 0))
                == "0 of 0 exercises complete")
    }

    @Test("The plan's three rep counts pluralise, one rep included")
    func planLinesPluraliseOnTheRepCount() {
        // `FR-15.3.2`'s deviation is off by one more often than by anything else, so "1 reps" is
        // the reading this would otherwise carry most of the time — the same argument the progress
        // line's plural is made on, one requirement later.
        #expect(String(localized: LoggingStrings.sessionPlanRepsDelta(1)) == "1 rep")
        #expect(String(localized: LoggingStrings.sessionPlanRepsDelta(2)) == "2 reps")
        #expect(
            String(localized: LoggingStrings.sessionPlanTarget(weight: "100 kg", reps: 1))
                == "Target 100 kg × 1 rep")
        #expect(
            String(localized: LoggingStrings.sessionPlanTarget(weight: "85 kg", reps: 8))
                == "Target 85 kg × 8 reps")
        #expect(
            String(localized: LoggingStrings.sessionPlanTargetOpenLoad(reps: 1))
                == "Target 1 rep, load your own")
        #expect(
            String(localized: LoggingStrings.sessionPlanTargetOpenLoad(reps: 5))
                == "Target 5 reps, load your own")
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
