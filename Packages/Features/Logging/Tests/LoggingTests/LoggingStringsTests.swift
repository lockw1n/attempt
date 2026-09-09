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

    /// `FR-17.1.6` and `D-17.7`: one word names the sheet, and three spellings are retired.
    ///
    /// **A string test rather than a review note**, because the words are the requirement: the row
    /// command that opens the sheet and the sheet's own heading have to be the same word, and *Add
    /// set*, *Log set* and *Adjust* have to be gone from **both** catalogues rather than from the
    /// one a reviewer happened to read.
    @Test("One word names the Log sheet, and the retired spellings are gone from both catalogues")
    func oneWordNamesTheSheet() {
        #expect(String(localized: LoggingStrings.dayLogAction) == "Log")
        #expect(String(localized: LoggingStrings.setEditorTitle) == "Log")
        #expect(String(localized: LoggingStrings.setEditorQuestion) == "What did you do?")
        #expect(String(localized: LoggingStrings.setSaveDoneAction) == "Save as done")
        // The free workout's edit keeps its own words — this phase does not redesign it
        // (`OUT-17.8`).
        #expect(String(localized: LoggingStrings.setEditorEditTitle) == "Edit set")

        // The three retirements, over every string either catalogue can draw. The Ukrainian half is
        // covered by `everyKeyResolves` above plus `check-translations.sh`: what can be asserted
        // here is that no English key still spells one of them.
        let retired = ["Add set", "Log set", "Adjust"]
        for resource in LoggingStrings.all {
            let rendered = String(localized: resource)
            for spelling in retired {
                #expect(rendered != spelling, "\(resource.key) still reads \(spelling)")
            }
        }
    }

    /// `FR-16.4.1`, and the half of it a picture cannot settle: a set nobody attempted announces
    /// itself as *pending*, and the word is not the failed one.
    @Test("A pending set announces itself as pending, not as failed")
    func pendingIsNotAnnouncedAsFailed() {
        let pending = String(localized: LoggingStrings.setOutcome(.pending))
        let failed = String(localized: LoggingStrings.setOutcome(.failed))
        let completed = String(localized: LoggingStrings.setOutcome(.completed))

        #expect(pending == "Pending")
        #expect(failed == "Failed")
        #expect(pending != failed)
        #expect(pending != completed)
    }

    /// `FR-16.4.4`'s alert, whose copy is the whole of the design and which no reference can hold:
    /// an alert is presented by the system, and `ImageRenderer` draws the view under it.
    @Test("Finish asks about pending sets by name, and offers both answers plus a way back")
    func theFinishQuestionIsAsked() {
        #expect(
            String(localized: LoggingStrings.sessionFinishPendingTitle(3))
                == "3 sets were not logged")
        // The plural is the reason this key is in the stringsdict rather than the table: the verb
        // agrees with the count, so one set cannot be spelled by substituting a numeral.
        #expect(
            String(localized: LoggingStrings.sessionFinishPendingTitle(1))
                == "1 set was not logged")
        #expect(String(localized: LoggingStrings.sessionFinishPendingRemove) == "Remove them")
        #expect(String(localized: LoggingStrings.sessionFinishPendingKeep) == "Keep as failed")
        // Naming what it keeps rather than saying "cancel": leaving the alert leaves the workout
        // open, which is the one outcome the other two do not offer.
        #expect(
            String(localized: LoggingStrings.sessionFinishPendingCancel) == "Back to the workout")
    }

    /// `FR-17.9.9`'s two confirmations, whose copy is the whole of the design and which no
    /// reference can hold: a `confirmationDialog` is presented by the system, and on iOS 26 it
    /// renders as a popover that drops its cancel — so the count and the destructive word are what
    /// a lifter is actually asked, and only a string test can see them.
    @Test("The whole-day commands name their count, and offer a way back that says what it keeps")
    func theWholeDayCommandsAskByName() {
        #expect(
            String(localized: LoggingStrings.dayLogRemainingConfirmTitle(count: 3))
                == "Log 3 exercises as planned?")
        #expect(
            String(localized: LoggingStrings.daySkipRemainingConfirmTitle(count: 2))
                == "Skip 2 exercises?")
        // The plural is why both keys are in the stringsdict rather than the table: one exercise
        // cannot be spelled by substituting a numeral.
        #expect(
            String(localized: LoggingStrings.dayLogRemainingConfirmTitle(count: 1))
                == "Log 1 exercise as planned?")
        #expect(
            String(localized: LoggingStrings.daySkipRemainingConfirmTitle(count: 1))
                == "Skip 1 exercise?")
        #expect(String(localized: LoggingStrings.dayLogRemainingConfirmAction) == "Log them")
        #expect(String(localized: LoggingStrings.daySkipRemainingConfirmAction) == "Skip them")
        // Naming what it keeps rather than saying "cancel", on the discard dialog's rule.
        #expect(String(localized: LoggingStrings.dayRemainingConfirmCancel) == "Keep going")
    }

    /// `FR-17.9.7`'s overflow menu, on both of its hosts. A menu is not snapshottable — T-16.04's
    /// finding on dialogs applies — so its two items and its own name are asserted here.
    @Test("The overflow menu carries both items, and is named for neither")
    func theOverflowMenuCarriesBothItems() {
        #expect(String(localized: LoggingStrings.dayChangeDateAction) == "Change date")
        #expect(String(localized: LoggingStrings.sessionDiscardAction) == "Discard workout")
        // Named for the menu rather than for either item in it (`G-4.2`, `NFR-1.10`): a button
        // announcing itself as **Discard** would be lying about the half that changes a date.
        let menu = String(localized: LoggingStrings.dayMenuAction)
        #expect(menu == "Day options")
        #expect(menu != String(localized: LoggingStrings.dayChangeDateAction))
        #expect(menu != String(localized: LoggingStrings.sessionDiscardAction))
    }

    /// `FR-17.9.6`: a skip is an outcome, and it is not the word a done row uses.
    @Test("Skipped and done are different words")
    func skippedIsNotDone() {
        let skipped = String(localized: LoggingStrings.dayRowSkipped)
        #expect(skipped == "Skipped")
        #expect(skipped != String(localized: LoggingStrings.dayRowDone))
    }

    @Test("The catalogue is this module's, not the app's")
    func copyComesFromTheModuleBundle() {
        #expect(Bundle.module.localizations.sorted() == ["en", "uk"])
        #expect(String(localized: LoggingStrings.weekPlanAction) == "Plan your week")
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
        #expect(catalogue["logging.week.plan.action"] == "Запланувати тиждень")
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

    /// `FR-17.2.3`: `RM` is never written, and the badge key that wrote it leaves both catalogues
    /// along with its English value.
    ///
    /// **`check-translations.sh` compares the two catalogues to each other**, so a key retired from
    /// both is invisible to it — this module's badge is where `PR %lldRM` was drawn, and the
    /// `Dashboard` and `ExerciseLibrary` suites each assert their own half of the same retirement.
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
            for key in [
                "logging.session.set.record.rep-max %lld",
                "logging.session.set.record.rep-max.label %lld",
            ] {
                #expect(catalogue[key] == nil, "\(localization) kept \(key)")
            }
            #expect(
                !catalogue.values.contains { $0.contains("%lldRM") || $0.contains("%lldПМ") },
                "\(localization) still writes a rep max as RM")
            #expect(
                !catalogue.values.contains { $0.localizedCaseInsensitiveContains("rep max") },
                "\(localization) still writes \"rep max\"")
        }
    }

    @Test("The badge's rep count pluralises, which is what a 1RM is badged with")
    func theBadgeRepCountPluralises() {
        // A record at a single rep is the 1RM, so `PR · 1 reps` would be the badge on the most
        // visible record a lifter sets — and on what VoiceOver reads over it (`G-3.4`).
        #expect(String(localized: LoggingStrings.setPersonalRecordReps(1)) == "PR · 1 rep")
        #expect(String(localized: LoggingStrings.setPersonalRecordReps(8)) == "PR · 8 reps")
        #expect(String(localized: LoggingStrings.setFirstPerformanceReps(1)) == "First · 1 rep")
        #expect(
            String(localized: LoggingStrings.setPersonalRecordRepsLabel(1))
                == "Personal record, 1 rep")
        #expect(
            String(localized: LoggingStrings.setFirstPerformanceRepsLabel(1)) == "First time, 1 rep")
        #expect(
            String(localized: LoggingStrings.setFirstPerformanceRepsLabel(3))
                == "First time, 3 reps")
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
