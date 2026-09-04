import Foundation
import RepositoryInterface

/// This module's copy (`G-3.4`), and the only place a dashboard string literal is written.
///
/// Each entry names a key in `Resources/en.lproj/Localizable.strings` and binds it to this module's
/// own bundle. The key convention is documented once, in `Localization`.
enum DashboardStrings {
    /// The recent-PR feed's heading, and the pushed screen's own title (`FR-1.6.5`, `FR-1.9.3`).
    ///
    /// **One string for both**, because the card and the screen behind it are the same list at two
    /// lengths — two spellings would let a translation make them look like different features.
    static let recentRecordsTitle = resource("dashboard.recent-records.title")

    /// Why the feed is empty, and what would fill it (`FR-1.13.3`, `FR-1.6.1`).
    ///
    /// **Two sentences, and the second is the one no other screen says.** A set that fell short of
    /// its target keeps the reps it reached (`FR-1.2.5`) and still sets no record, because
    /// `TR-0.2.8` counts completed sets only — and it counts them only because `isCompleted` is
    /// `false` on a set that was never performed as well as on one that failed, so reps read out of
    /// an incomplete set would credit a record to training that did not happen. That refusal is
    /// correct and invisible: an empty feed after a hard session reads as a bug.
    static let recentRecordsNone = resource("dashboard.recent-records.none")

    /// Why the feed could not be read.
    static let recentRecordsError = resource("dashboard.recent-records.error")

    /// The control that opens the full list from the card.
    static let recentRecordsSeeAll = resource("dashboard.recent-records.see-all")

    /// What one entry is the record for, where the run set a rep max — `8RM` (`FR-16.3.3`).
    ///
    /// **The top of what it took, never the span of it.** A set of eight that beat every N up to
    /// eight is an 8RM; writing it "1–8-rep max" states eight claims where the lifter made one, and
    /// the seven below it are the arithmetic rather than the achievement. That label is retired.
    ///
    /// **The compound carries no plural**, so no rule file is needed: the numeral sits inside `8RM`.
    ///
    /// - Parameter reps: The highest N the run holds at a single set.
    /// - Returns: The label.
    static func recentRecordsRepMax(_ reps: Int) -> LocalizedStringResource {
        resource("dashboard.recent-records.rep-max \(reps)")
    }

    /// What one entry is the record for, where the run set no single-set rep max at all
    /// (`FR-16.2.1`).
    ///
    /// **The lifter's own notation, `reps × sets`**, rather than a sentence: a run whose records all
    /// stand at two sets and up has no N-rep max to name, and "5 × 5" is what the training log it
    /// came from calls it. The compound carries no plural, so no rule file is needed.
    ///
    /// - Parameters:
    ///   - reps: The maximal scheme's repetitions.
    ///   - sets: How many consecutive sets it asks for.
    /// - Returns: The label.
    static func recentRecordsScheme(_ reps: Int, _ sets: Int) -> LocalizedStringResource {
        resource("dashboard.recent-records.scheme \(reps) \(sets)")
    }

    /// The set that produced a record, as `FR-16.3.3`'s row names it — `145 kg × 8`.
    ///
    /// **The load and the numbers arrive already rendered**, on
    /// ``Logging/LoggingStrings/setRPE(_:)``' rule: they are formatted for the locale by the caller's
    /// own formatter (`G-3.4`), and what this string owns is the punctuation between them.
    ///
    /// - Parameters:
    ///   - load: The record load, formatted.
    ///   - reps: The repetitions, formatted.
    /// - Returns: The reading.
    static func recentRecordsSet(_ load: String, _ reps: String) -> LocalizedStringResource {
        resource("dashboard.recent-records.set \(load) \(reps)")
    }

    /// The same, where the record stands over a run of sets — `100 kg × 5 × 5`.
    ///
    /// - Parameters:
    ///   - load: The record load, formatted.
    ///   - reps: The repetitions, formatted.
    ///   - sets: How many consecutive sets, formatted.
    /// - Returns: The reading.
    static func recentRecordsRun(
        _ load: String, _ reps: String, _ sets: String
    ) -> LocalizedStringResource {
        resource("dashboard.recent-records.run \(load) \(reps) \(sets)")
    }

    /// What stands where the delta would, for a scheme performed for the first time (`FR-16.3.4`).
    ///
    /// **A word rather than a blank.** A baseline and a record whose delta could not be worked out
    /// would otherwise look the same, and the first time a lifter performs a scheme is the one
    /// occasion there is nothing to have beaten — which is worth saying.
    static let recentRecordsBaseline = resource("dashboard.recent-records.baseline")

    /// What tapping a feed entry does.
    static let recentRecordsExerciseHint = resource("dashboard.recent-records.exercise-hint")

    /// Why the feed is empty under a scope narrower than every exercise (`FR-16.3.4`).
    ///
    /// **A different sentence from ``recentRecordsNone``, not a variant of it.** That one explains
    /// what a set has to be before it sets a record, which is the wrong thing to tell a lifter whose
    /// records exist and are outside the scope they chose.
    static let recentRecordsNoneInScope = resource("dashboard.recent-records.none-in-scope")

    /// `FR-16.3.4`'s offer: the wider scope, as the button that takes it.
    static let recentRecordsShowEveryExercise = resource("dashboard.recent-records.show-every")

    /// The configuration screen's title (`FR-16.3.1`), and the Settings row that opens it.
    static let recentRecordsSettingsTitle = resource("dashboard.recent-records.settings.title")

    /// The configuration could not be read.
    static let recentRecordsSettingsError = resource("dashboard.recent-records.settings.error")

    /// A change to it could not be stored. Nothing moved.
    static let recentRecordsSettingsWriteError = resource(
        "dashboard.recent-records.settings.write-error")

    /// `FR-16.3.1`'s heading.
    static let recentRecordsScopeTitle = resource("dashboard.recent-records.scope.title")

    /// What choosing a narrower scope does, and where the first option's list comes from.
    static let recentRecordsScopeDetail = resource("dashboard.recent-records.scope.detail")

    /// One scope's name (`FR-16.3.1`).
    ///
    /// **A function over the vocabulary rather than three constants**, on
    /// ``Settings/SettingsStrings/themeName(for:)``' rule: the enum is the list the picker draws, so
    /// a case added without a name is a compile error rather than a blank row.
    ///
    /// - Parameter scope: The scope.
    /// - Returns: Its name.
    static func recentRecordsScopeName(for scope: RecentRecordsScope) -> LocalizedStringResource {
        switch scope {
        case .dashboardLifts: resource("dashboard.recent-records.scope.dashboard-lifts")
        case .everyExercise: resource("dashboard.recent-records.scope.every-exercise")
        case .chosen: resource("dashboard.recent-records.scope.chosen")
        }
    }

    /// The heading over the chosen scope's own exercise list.
    static let recentRecordsExercisesTitle = resource("dashboard.recent-records.exercises.title")

    /// The catalogue holds nothing to choose from.
    static let recentRecordsExercisesEmpty = resource("dashboard.recent-records.exercises.empty")

    /// `FR-16.3.2`'s heading.
    static let recentRecordsSchemesTitle = resource("dashboard.recent-records.schemes.title")

    /// The switch between derived and chosen schemes.
    static let recentRecordsSchemesDerived = resource("dashboard.recent-records.schemes.derived")

    /// What "derived" means, in the threshold the requirement names.
    static let recentRecordsSchemesDetail = resource("dashboard.recent-records.schemes.detail")

    /// The scope holds no record to choose a scheme from.
    static let recentRecordsSchemesEmpty = resource("dashboard.recent-records.schemes.empty")

    /// `FR-16.3.4`'s heading.
    static let recentRecordsBaselinesTitle = resource("dashboard.recent-records.baselines.title")

    /// The toggle itself.
    static let recentRecordsBaselinesLabel = resource("dashboard.recent-records.baselines.label")

    /// Why it is off to begin with.
    static let recentRecordsBaselinesDetail = resource("dashboard.recent-records.baselines.detail")

    /// `FR-1.9.4`'s primary action, which navigates to Train rather than logging anything here.
    ///
    /// **Also `FR-1.13.2`'s action**, where the first-launch state carries it instead of the button.
    static let startWorkout = resource("dashboard.start.action")

    /// `FR-1.13.2`'s heading: an install with nothing in it.
    static let firstLaunchHeadline = resource("dashboard.first-launch.headline")

    /// What logging one workout turns this screen into.
    static let firstLaunchMessage = resource("dashboard.first-launch.message")

    /// `FR-1.9.5`'s heading.
    static let weekTitle = resource("dashboard.week.title")

    /// What the first of `FR-1.9.5`'s two numbers counts.
    static let weekWorkouts = resource("dashboard.week.workouts")

    /// What the second of them weighs.
    static let weekVolume = resource("dashboard.week.volume")

    /// Nothing this week counts as training done (`FR-1.13.3`).
    static let weekNone = resource("dashboard.week.none")

    /// Training happened and none of it can be weighed — `Tonnage`'s third clause, said out loud.
    static let weekUnweighed = resource("dashboard.week.unweighed")

    /// The sessions could not be read.
    static let weekError = resource("dashboard.week.error")

    /// `FR-1.9.2`'s heading.
    static let lastWorkoutTitle = resource("dashboard.last-workout.title")

    /// Nothing has ever been logged.
    static let lastWorkoutNone = resource("dashboard.last-workout.none.headline")

    /// What to do about it — the action itself is the button above this card.
    static let lastWorkoutNoneMessage = resource("dashboard.last-workout.none.message")

    /// The sessions could not be read.
    static let lastWorkoutError = resource("dashboard.last-workout.error")

    /// The workout on the card has not been finished.
    static let lastWorkoutInProgress = resource("dashboard.last-workout.in-progress")

    /// `FR-1.9.2`'s resume, for a workout still open.
    static let lastWorkoutResume = resource("dashboard.last-workout.resume")

    /// `FR-1.9.2`'s repeat: a fresh workout holding the same exercises and no sets.
    static let lastWorkoutRepeat = resource("dashboard.last-workout.repeat")

    /// The repeat could not be started. Nothing was written.
    static let lastWorkoutRepeatError = resource("dashboard.last-workout.repeat-error")

    /// How much work a finished session holds.
    ///
    /// - Parameter count: The working sets — completed, and not warmups (`G-1.8`).
    /// - Returns: The line.
    static func lastWorkoutSets(_ count: Int) -> LocalizedStringResource {
        resource("dashboard.last-workout.sets \(count)")
    }

    /// Every string this module owns, for the test that asserts each one resolves.
    static var all: [LocalizedStringResource] {
        [
            recentRecordsTitle, recentRecordsNone, recentRecordsError, recentRecordsSeeAll,
            recentRecordsRepMax(3), recentRecordsScheme(5, 5),
            recentRecordsSet("145 kg", "8"), recentRecordsRun("100 kg", "5", "5"),
            recentRecordsBaseline, recentRecordsExerciseHint,
            recentRecordsNoneInScope, recentRecordsShowEveryExercise,
            recentRecordsSettingsTitle, recentRecordsSettingsError,
            recentRecordsSettingsWriteError,
            recentRecordsScopeTitle, recentRecordsScopeDetail,
            recentRecordsExercisesTitle, recentRecordsExercisesEmpty,
            recentRecordsSchemesTitle, recentRecordsSchemesDerived, recentRecordsSchemesDetail,
            recentRecordsSchemesEmpty,
            recentRecordsBaselinesTitle, recentRecordsBaselinesLabel,
            recentRecordsBaselinesDetail,
            startWorkout, lastWorkoutTitle, lastWorkoutNone, lastWorkoutNoneMessage,
            lastWorkoutError, lastWorkoutInProgress, lastWorkoutResume, lastWorkoutRepeat,
            lastWorkoutRepeatError, lastWorkoutSets(4),
            firstLaunchHeadline, firstLaunchMessage,
            weekTitle, weekWorkouts, weekVolume, weekNone, weekUnweighed, weekError,
            tilesTitle, tilesError, tilesNoneChosen, tilesNoneChosenMessage, tileManual,
            tileNoPrevious, tilesChooseAction, tilesChooseTitle, tilesChooseEmpty,
            tilesChooseError, tilesChooseWriteError,
        ] + absences.map { tileAbsence($0, days: 90) }
            + RecentRecordsScope.allCases.map { recentRecordsScopeName(for: $0) }
    }

    /// Binds a key to this module's catalogue.
    static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
