import Foundation

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

    /// Why the feed is empty, and what would fill it (`FR-1.13.3`).
    static let recentRecordsNone = resource("dashboard.recent-records.none")

    /// Why the feed could not be read.
    static let recentRecordsError = resource("dashboard.recent-records.error")

    /// The control that opens the full list from the card.
    static let recentRecordsSeeAll = resource("dashboard.recent-records.see-all")

    /// What one entry is the record for, where the set holds a single N.
    ///
    /// - Parameter reps: The N.
    /// - Returns: The label.
    static func recentRecordsRepMax(_ reps: Int) -> LocalizedStringResource {
        resource("dashboard.recent-records.rep-max \(reps)")
    }

    /// What one entry is the record for, where the set holds several N's at once.
    ///
    /// **A range rather than a plural**, so no rule file is needed: the noun is "max" and both
    /// numbers sit inside the compound before it, which reads the same at every count.
    ///
    /// - Parameters:
    ///   - lowest: The lowest N the set holds.
    ///   - highest: The highest.
    /// - Returns: The label.
    static func recentRecordsRepMaxRange(_ lowest: Int, _ highest: Int) -> LocalizedStringResource {
        resource("dashboard.recent-records.rep-max.range \(lowest) \(highest)")
    }

    /// What tapping a feed entry does.
    static let recentRecordsExerciseHint = resource("dashboard.recent-records.exercise-hint")

    /// `FR-1.9.4`'s primary action, which navigates to Train rather than logging anything here.
    static let startWorkout = resource("dashboard.start.action")

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
            recentRecordsRepMax(3), recentRecordsRepMaxRange(1, 3), recentRecordsExerciseHint,
            startWorkout, lastWorkoutTitle, lastWorkoutNone, lastWorkoutNoneMessage,
            lastWorkoutError, lastWorkoutInProgress, lastWorkoutResume, lastWorkoutRepeat,
            lastWorkoutRepeatError, lastWorkoutSets(4),
            tilesTitle, tilesError, tilesNoneChosen, tilesNoneChosenMessage, tileManual,
            tileNoPrevious, tilesChooseAction, tilesChooseTitle, tilesChooseEmpty,
            tilesChooseError, tilesChooseWriteError,
        ] + absences.map { tileAbsence($0, days: 90) }
    }

    /// Binds a key to this module's catalogue.
    static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
