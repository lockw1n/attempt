import DerivedValues
import Foundation
import PowerliftingCore
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
        #expect(Bundle.module.localizations.sorted() == ["en", "uk"])
        #expect(String(localized: DashboardStrings.recentRecordsTitle) == "Recent PRs")
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
        #expect(catalogue["dashboard.recent-records.title"] == "Нові рекорди")
    }

    @Test("The catalogue and the accessors name exactly the same keys")
    func catalogueAndAccessorsAgree() throws {
        // Two files, one catalogue, on `LoggingStrings`' shape since `FR-17.2.3`: a feed row's
        // single-set label is a plural, which only the `.stringsdict` can express, and a key in one
        // file must not also be in the other.
        let strings = try Self.keys(inCatalogueNamed: "strings")
        let plurals = try Self.keys(inCatalogueNamed: "stringsdict")
        #expect(strings.isDisjoint(with: plurals))
        #expect(strings.union(plurals) == Set(DashboardStrings.all.map(\.key)))
        #expect(!strings.isEmpty)
        #expect(!plurals.isEmpty)
    }

    @Test("A single-set row pluralises, which is what a 1RM reads as")
    func theSingleSetLabelPluralises() {
        // The reason this module gained a `.stringsdict`. The one-rep case is the 1RM rather than
        // an edge case, and a `.strings` format cannot fix it — the numeral is the one the noun
        // agrees with (`G-3.4`).
        #expect(String(localized: DashboardStrings.recentRecordsReps(1)) == "1 rep")
        #expect(String(localized: DashboardStrings.recentRecordsReps(2)) == "2 reps")
        #expect(String(localized: DashboardStrings.recentRecordsReps(8)) == "8 reps")
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

    @Test("Keys follow the convention: lowercase, dotted, module-prefixed")
    func keysFollowTheConvention() {
        for resource in DashboardStrings.all {
            let key = resource.key
            #expect(key.hasPrefix("dashboard."), "\(key) does not name its module")
            #expect(key.split(separator: ".").count >= 3, "\(key) is too shallow")
            #expect(key == key.lowercased(), "\(key) is not lowercase")
        }
    }

    /// `D-17.11`: `FR-1.9.4`'s **Start workout** is withdrawn, and a withdrawal that already
    /// shipped has to leave the catalogues as well as the screen.
    ///
    /// **Both catalogues, read as files**, rather than the accessors alone: `DashboardStrings.all`
    /// can only say what the code still *names*, and a key left behind in `uk.lproj` with no
    /// accessor is exactly the leftover `check-translations.sh` cannot see either — it compares the
    /// two catalogues to each other, so a key present in both is complete and wrong.
    ///
    /// The guided action's own words are asserted here rather than in a picture, because what makes
    /// them right is that they match the Train tab's empty state (`FR-17.8.5`) and a reference
    /// cannot compare two modules.
    @Test("The first launch offers Plan your week, and Start workout is in neither catalogue")
    func theGuidedActionPlansTheWeek() throws {
        #expect(String(localized: DashboardStrings.planWeek) == "Plan your week")

        for localization in ["en", "uk"] {
            let url = try #require(
                Bundle.module.url(
                    forResource: "Localizable",
                    withExtension: "strings",
                    subdirectory: nil,
                    localization: localization
                ))
            let catalogue = try #require(NSDictionary(contentsOf: url) as? [String: String])
            #expect(catalogue["dashboard.plan-week.action"] != nil)
            #expect(catalogue["dashboard.start.action"] == nil, "\(localization) kept the key")
            #expect(
                !catalogue.values.contains("Start workout"),
                "\(localization) still reads Start workout")
        }
    }

    /// The two forms are one label at two shapes, and each has to keep every number it was
    /// given — a translation that dropped one would read as the wrong record.
    @Test("A single set and a run read as different labels")
    func theTwoRecordFormsDiffer() {
        #expect(String(localized: DashboardStrings.recentRecordsReps(3)) == "3 reps")
        #expect(String(localized: DashboardStrings.recentRecordsScheme(5, 5)) == "5×5")
    }

    /// `FR-17.2.3`: `RM` is never written, and the key that wrote it leaves both catalogues along
    /// with its English value — `check-translations.sh` compares the two to each other, so a key
    /// retired from both is invisible to it.
    @Test("The RM notation is gone from both catalogues")
    func theRepMaxNotationIsRetired() throws {
        for localization in ["en", "uk"] {
            let url = try #require(
                Bundle.module.url(
                    forResource: "Localizable",
                    withExtension: "strings",
                    subdirectory: nil,
                    localization: localization
                ))
            let catalogue = try #require(NSDictionary(contentsOf: url) as? [String: String])
            #expect(
                catalogue["dashboard.recent-records.rep-max %lld"] == nil,
                "\(localization) kept the key")
            // Its replacement is in the `.stringsdict`, so its absence here is not the check.
            #expect(catalogue["dashboard.recent-records.reps %lld"] == nil)
            // The estimated-1RM tile keeps its own `1RM`, which `FR-16.2.5` leaves untouched — so
            // this is the record label's form specifically: a numeral placeholder against `RM`.
            #expect(
                !catalogue.values.contains { $0.contains("%lldRM") || $0.contains("%lldПМ") },
                "\(localization) still writes a rep max as RM")
        }
    }

    /// `FR-17.2.3`: which of the two spellings a row gets is decided off the record's set count,
    /// not inside a `View` — and the row names the one cell the run holds (`FR-17.2.1`).
    @Test("A feed row is labelled by the cell the run was performed at")
    func aFeedRowIsLabelledByWhatItSet() {
        #expect(String(localized: label(reps: 3, sets: 1)) == "3 reps")
        #expect(String(localized: label(reps: 8, sets: 1)) == "8 reps")
        #expect(String(localized: label(reps: 5, sets: 5)) == "5×5")
        // A run of two takes the scheme spelling, so the switch is the set count and not "more than
        // a handful of sets".
        #expect(String(localized: label(reps: 5, sets: 2)) == "5×2")
    }

    /// `FR-16.3.3`: the set that produced the record, written the way the log writes it.
    @Test("A run's reading carries its set count and a single set's does not")
    func aRunReadsAsThreeNumbersAndASetAsTwo() {
        #expect(String(localized: DashboardStrings.recentRecordsSet("145 kg", "8")) == "145 kg × 8")
        #expect(
            String(localized: DashboardStrings.recentRecordsRun("100 kg", "5", "5"))
                == "100 kg × 5 × 5")
    }

    /// `FR-16.3.3`: which of the two readings a row gets is decided off the record, on
    /// ``Dashboard/RecentRecord/feedLabel``'s rule — the set count alone, and not inside a `View`.
    @Test("A record standing at one set reads without a set count and a run reads with one")
    func aReadingIsChosenByTheRecordsSetCount() {
        #expect(
            String(
                localized: record(reps: 8, sets: 1)
                    .sourceReading(load: "145 kg", reps: "8", sets: "1")) == "145 kg × 8")
        #expect(
            String(
                localized: record(reps: 5, sets: 5)
                    .sourceReading(load: "100 kg", reps: "5", sets: "5")) == "100 kg × 5 × 5")
    }

    /// One feed row's record, stating only what the labels read.
    private func record(reps: Int, sets: Int) -> RecentRecord {
        RecentRecord(
            exerciseID: UUID(),
            scheme: RecordScheme(reps: reps, sets: sets),
            weight: Weight(grams: 100_000),
            sourceSetID: UUID(),
            achievedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    /// One feed row's label, over a record stating only what the label reads.
    private func label(reps: Int, sets: Int) -> LocalizedStringResource {
        record(reps: reps, sets: sets).feedLabel
    }
}
