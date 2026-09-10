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

    /// `FR-16.2.4`'s table copy. The cell label is the one that has to be asserted rather than
    /// merely resolved: the cell draws neither of its headings, so `G-4.2`'s reading is the only
    /// place its scheme is spoken at all, and "by" rather than "×" is the whole point of it.
    @Test("The table's headings, its notation and the cell VoiceOver reads")
    func theSchemeTableCopyReads() {
        #expect(String(localized: ExerciseLibraryStrings.recordsRepsHeader) == "reps")
        #expect(String(localized: ExerciseLibraryStrings.recordsSetColumn(5)) == "× 5")
        // `FR-17.2.3`: the one-set column is a word, and never `× 1`.
        #expect(String(localized: ExerciseLibraryStrings.recordsSetColumn(1)) == "single")
        #expect(String(localized: ExerciseLibraryStrings.recordsScheme(5, 5)) == "5×5")
        #expect(
            String(
                localized: ExerciseLibraryStrings.recordsCellLabel(
                    reps: 5, sets: 5, load: "100 kg", date: "1 May")) == "5 by 5, 100 kg, 1 May")
    }

    /// `FR-17.2.2`'s other two cell states, and `Q-17.1`'s words for them. The two spoken labels
    /// name their scheme for ``ExerciseLibraryStrings/recordsCellLabel(reps:sets:load:date:)``'s
    /// reason — a reader moving across a grid carries neither heading with them.
    @Test("The first-performance and never-performed cells read as states, not as numbers")
    func theTwoOtherCellStatesRead() {
        #expect(String(localized: ExerciseLibraryStrings.recordsCellNotYet) == "Not yet")
        #expect(
            String(localized: ExerciseLibraryStrings.recordsCellFirst(date: "1 May"))
                == "First · 1 May")
        #expect(
            String(localized: ExerciseLibraryStrings.recordsCellNotYetLabel(reps: 5, sets: 5))
                == "5 by 5, not yet")
        #expect(
            String(
                localized: ExerciseLibraryStrings.recordsCellFirstLabel(
                    reps: 5, sets: 5, load: "100 kg", date: "1 May"))
                == "5 by 5, first time, 100 kg, 1 May")
    }

    /// `FR-17.5.1` and `FR-17.5.2`: the absent line's two halves, the command said twice at two
    /// lengths, and the field that no longer repeats the sheet's title.
    ///
    /// **The sheet's title and its first field are asserted to differ**, which is the whole of
    /// review finding 15's copy half: *Training max* as navigation title, section heading, prompt
    /// and VoiceOver label is one word said four times before anything is typed.
    @Test("The training max line is three words, and the sheet names itself once")
    func theTrainingMaxLineAndSheetCopyRead() {
        #expect(String(localized: ExerciseLibraryStrings.trainingMaxNoneLine) == "No training max")
        #expect(String(localized: ExerciseLibraryStrings.trainingMaxSetOneAction) == "Set one")
        #expect(String(localized: ExerciseLibraryStrings.trainingMaxChangeOneAction) == "Change")
        // The same two commands in full, which is what VoiceOver is given: two words written to
        // end a line are a fragment read out on their own.
        #expect(String(localized: ExerciseLibraryStrings.trainingMaxSetAction) == "Set training max")
        #expect(
            String(localized: ExerciseLibraryStrings.trainingMaxChangeAction)
                == "Change training max")
        #expect(String(localized: ExerciseLibraryStrings.trainingMaxFormTitle) == "Training max")
        #expect(String(localized: ExerciseLibraryStrings.trainingMaxWeightLabel) == "Weight")
    }

    /// `FR-17.2.3`: `RM` and "rep max" are retired as a record's notation, and the key that wrote
    /// them leaves both catalogues along with its English value — `check-translations.sh` compares
    /// the two catalogues to each other, so a key retired from both is invisible to it.
    @Test("The rep-max notation is gone from both catalogues")
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
                catalogue["exerciselibrary.detail.records.rep-max %lld"] == nil,
                "\(localization) kept the key")
            #expect(
                !catalogue.values.contains("%lld-rep max"),
                "\(localization) still writes a record as a rep max")
            // The disclosure over the 6–10 rows is the same notation one heading up, and renaming
            // the rows without it is the miss this assertion exists to catch.
            #expect(
                !catalogue.values.contains { $0.localizedCaseInsensitiveContains("rep max") },
                "\(localization) still writes \"rep max\"")
            // And the spaced scheme, which `FR-17.2.3` tightens so all three surfaces agree.
            #expect(
                !catalogue.values.contains("%1$lld × %2$lld"),
                "\(localization) still spaces the scheme")
        }
    }

    @Test("The catalogue is this module's, not the app's")
    func copyComesFromTheModuleBundle() {
        #expect(Bundle.module.localizations.sorted() == ["en", "uk"])
        #expect(String(localized: ExerciseLibraryStrings.searchPrompt) == "Search exercises")
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
        #expect(catalogue["exerciselibrary.list.title"] == "Вправи")
    }

    @Test("The catalogue and the accessors name exactly the same keys")
    func catalogueAndAccessorsAgree() throws {
        // Two files, one catalogue, on `LoggingStrings`' shape: `FR-16.1.1`'s set count is a plural,
        // which only the `.stringsdict` can express, and a key in one file must not also be in the
        // other.
        let strings = try Self.keys(inCatalogueNamed: "strings")
        let plurals = try Self.keys(inCatalogueNamed: "stringsdict")
        #expect(strings.isDisjoint(with: plurals))
        #expect(strings.union(plurals) == Set(ExerciseLibraryStrings.all.map(\.key)))
        #expect(!strings.isEmpty)
        #expect(!plurals.isEmpty)
    }

    @Test("A record row's rep count pluralises, and the one-rep row heads the list")
    func theRecordRowRepCountPluralises() {
        // `FR-17.2.3` spells a record `8 reps`, and the 1-rep row is the first line of this list —
        // so "1 reps" would be the reading a reader meets first (`G-3.4`).
        #expect(String(localized: ExerciseLibraryStrings.recordsReps(1)) == "1 rep")
        #expect(String(localized: ExerciseLibraryStrings.recordsReps(5)) == "5 reps")
    }

    @Test("A history row's set count pluralises, which a .strings format could not")
    func theSetCountPluralises() {
        // The reason this module gained a `.stringsdict`. A run of two would otherwise read
        // "2 set", and the numeral is the one the noun agrees with (`G-3.4`).
        #expect(String(localized: ExerciseLibraryStrings.historySets(2)) == "2 sets")
        #expect(String(localized: ExerciseLibraryStrings.historySets(1)) == "1 set")
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
