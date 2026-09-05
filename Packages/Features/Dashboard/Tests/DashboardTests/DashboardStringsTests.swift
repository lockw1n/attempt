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

    /// The two forms are one label at two shapes, and each has to keep every number it was
    /// given — a translation that dropped one would read as the wrong record.
    @Test("A rep max and a scheme read as different labels")
    func theTwoRecordFormsDiffer() {
        #expect(String(localized: DashboardStrings.recentRecordsRepMax(3)) == "3RM")
        #expect(String(localized: DashboardStrings.recentRecordsScheme(5, 5)) == "5 × 5")
    }

    /// `FR-16.3.3`: which of the two a row gets is decided off the record, not inside a `View`.
    ///
    /// **A span names its top and nothing below it.** A set of eight that beat every N up to eight
    /// is an 8RM; "1–8-rep max" states eight claims where the lifter made one, and that label is
    /// retired.
    ///
    /// The scheme case is the one the second dimension introduced — a run holding cells at two sets
    /// and up sets no rep max, and naming one would contradict the lifter's own history.
    @Test("A feed row is labelled by what the run actually set")
    func aFeedRowIsLabelledByWhatItSet() {
        #expect(String(localized: label(reps: 3, sets: 1, repMaxReps: 3...3)) == "3RM")
        #expect(String(localized: label(reps: 8, sets: 1, repMaxReps: 1...8)) == "8RM")
        #expect(String(localized: label(reps: 5, sets: 5, repMaxReps: nil)) == "5 × 5")
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
    private func record(
        reps: Int, sets: Int, repMaxReps: ClosedRange<Int>? = nil
    ) -> RecentRecord {
        RecentRecord(
            exerciseID: UUID(),
            scheme: RecordScheme(reps: reps, sets: sets),
            repMaxReps: repMaxReps,
            weight: Weight(grams: 100_000),
            sourceSetID: UUID(),
            achievedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    /// One feed row's label, over a record stating only what the label reads.
    private func label(
        reps: Int, sets: Int, repMaxReps: ClosedRange<Int>?
    ) -> LocalizedStringResource {
        record(reps: reps, sets: sets, repMaxReps: repMaxReps).feedLabel
    }
}
