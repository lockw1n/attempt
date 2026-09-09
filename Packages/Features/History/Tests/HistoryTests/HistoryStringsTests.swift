import Foundation
import RepositoryInterface
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

    /// Both empty states send the reader to Train's root, which is the week (`FR-17.8`) — so they
    /// offer the week's own words (`FR-17.8.5`), the same ones Home's first launch does.
    ///
    /// **Asserted as literals, because no test can compare two modules' catalogues.** Three screens
    /// in three packages name one destination; a reword in any of them has to fail somewhere, and
    /// this is where it fails for these two.
    @Test("Every empty state offers the week's own words")
    func theEmptyStatesNameTheDestination() {
        #expect(String(localized: HistoryStrings.emptyAction) == "Plan your week")
        #expect(String(localized: HistoryStrings.calendarEmptyAction) == "Plan your week")
        #expect(String(localized: HistoryStrings.weekEmptyAction) == "Plan your week")
    }

    /// A key the day section took with it when it retired (`FR-17.11.2`).
    ///
    /// **`scripts/check-translations.sh` cannot see this**: it compares the two catalogues to each
    /// other, so a key left in *both* is complete and wrong. ``catalogueAndAccessorsAgree`` covers
    /// the English half — the accessors no longer name it — and this covers the Ukrainian one, plus
    /// the copy itself, which is what a key renamed rather than removed would leave behind.
    @Test("The day section's copy left both catalogues with the screen")
    func theRetiredDayErrorIsGoneFromBothCatalogues() throws {
        for localization in ["en", "uk"] {
            let url = try #require(
                Bundle.module.url(
                    forResource: "Localizable",
                    withExtension: "strings",
                    subdirectory: nil,
                    localization: localization
                ))
            let catalogue = try #require(NSDictionary(contentsOf: url) as? [String: String])
            #expect(catalogue["history.calendar.day.error"] == nil)
            #expect(
                !catalogue.values.contains("Could not load that day's sessions."),
                "the retired copy survives in \(localization) under another key")
        }
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
        #expect(catalogue["history.list.empty.action"] == "Запланувати тиждень")
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

    /// `FR-16.4.4`'s alert asked from the history card, whose copy is the whole of the design and
    /// which no reference can hold: an alert is presented by the system, and `ImageRenderer` draws
    /// the view under it.
    @Test("Finishing from a card asks about pending sets by name, with both answers and a way back")
    func theFinishQuestionIsAsked() {
        #expect(
            String(localized: HistoryStrings.sessionPendingTitle(3)) == "3 sets were not logged")
        // The plural is why this key is in the stringsdict rather than the table: the verb agrees
        // with the count, so one set cannot be spelled by substituting a numeral.
        #expect(
            String(localized: HistoryStrings.sessionPendingTitle(1)) == "1 set was not logged")
        #expect(String(localized: HistoryStrings.sessionPendingRemove) == "Remove them")
        #expect(String(localized: HistoryStrings.sessionPendingKeep) == "Keep as failed")
        // Naming what it keeps rather than saying "cancel". The word differs from the training
        // tab's — there the way back is to the workout on screen, here it is to a row in a list.
        #expect(String(localized: HistoryStrings.sessionPendingCancel) == "Leave it open")
        #expect(String(localized: HistoryStrings.sessionFinish) == "Finish workout")
    }

    /// `FR-16.4.3`, and the half a reference cannot settle on its own: the two words are different
    /// words, and neither of them is a set count.
    @Test("An unfinished workout is named by its state, and planned is not in progress")
    func anUnfinishedWorkoutIsNamedByItsState() throws {
        let inProgress = String(localized: try #require(HistoryStrings.sessionState(.inProgress)))
        let planned = String(localized: try #require(HistoryStrings.sessionState(.planned)))

        #expect(inProgress == "In progress")
        #expect(planned == "Planned")
        // A finished workout has numbers to show, so it is answered with nothing at all.
        #expect(HistoryStrings.sessionState(.finished) == nil)
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
