import Foundation

/// ``LoggingStrings``' sixth file — `FR-15.3`'s planned-vs-actual copy, drawn on the workout in
/// progress.
///
/// **The same type in another file, on `LoggingModifierStrings.swift`'s argument**: one enum is
/// what keeps a module's copy in one place, and `file_length` is what keeps that one place
/// readable.
extension LoggingStrings {
    // MARK: - The exercise's check-off (FR-15.3.4)

    /// The caption on a card the lifter has checked off with work behind it.
    ///
    /// **A different word from `sessionExerciseCompleted`, because it is a different claim.** That
    /// one is the sets speaking — every working set logged and completed; this one is the lifter,
    /// and the two are reached independently.
    static let sessionExerciseMarkedDone = resource("logging.session.exercise.marked-done")

    /// The caption on a card checked off with none of the work behind it.
    ///
    /// A skip is an outcome the plan has to be able to record, not a card left looking untouched.
    static let sessionExerciseSkipped = resource("logging.session.exercise.skipped")

    /// The check-off itself, in whichever direction it would go next (`FR-15.3.4`).
    ///
    /// - Parameter isDone: Whether the exercise is already checked off.
    /// - Returns: The command's label.
    static func sessionExerciseDoneAction(isDone: Bool) -> LocalizedStringResource {
        isDone
            ? resource("logging.session.exercise.done.undo")
            : resource("logging.session.exercise.done.action")
    }

    // MARK: - The plan on the card (FR-15.3.1)

    /// The heading over what the routine prescribed next for this exercise.
    static let sessionPlanNextHeading = resource("logging.session.plan.next.heading")

    /// The one-tap command that logs the next planned set exactly as prescribed (`NFR-15.3`).
    static let sessionPlanLogAction = resource("logging.session.plan.log.action")

    /// A target as it is drawn beside a set — a rendered load and a repetition count.
    ///
    /// **The load arrives rendered and the reps arrive as a number**, which is
    /// ``LoggingStrings/equipmentPlatePairs(plate:pairs:)``' split for the same reason: `AppFormat`
    /// is what decides how a weight reads and a catalogue cannot, while the rep count has to reach
    /// the catalogue as a number for the plural rule to see it (`G-3.4`).
    ///
    /// - Parameters:
    ///   - weight: The prescribed load, rendered.
    ///   - reps: The prescribed repetitions.
    /// - Returns: The target line.
    static func sessionPlanTarget(weight: String, reps: Int) -> LocalizedStringResource {
        resource("logging.session.plan.target \(weight) \(reps)")
    }

    /// The same line for a group that prescribed no load (`FR-15.2.2`).
    ///
    /// **A third state in words, not an absence.** A blank target is not a target of zero and not a
    /// missing target — it prescribes the reps and leaves the load to the lifter, and a line that
    /// simply dropped the weight would read as a plan that forgot it.
    ///
    /// - Parameter reps: The prescribed repetitions.
    /// - Returns: The target line.
    static func sessionPlanTargetOpenLoad(reps: Int) -> LocalizedStringResource {
        resource("logging.session.plan.target-open \(reps)")
    }

    // MARK: - Deviation (FR-15.3.2)

    /// What a set that matched its target says, in a word (`G-4.5`).
    static let sessionPlanOnTarget = resource("logging.session.plan.on-target")

    /// A repetition deviation's magnitude, for the indicator that draws the direction.
    ///
    /// **Rendered as "2 reps" rather than as a bare numeral**, because it is drawn beside a load
    /// deviation that carries its own unit — and read aloud, two signed numerals in a row are two
    /// facts nothing tells apart. Plural, because one is the commonest miss there is.
    ///
    /// - Parameter reps: How many, unsigned.
    /// - Returns: The magnitude.
    static func sessionPlanRepsDelta(_ reps: Int) -> LocalizedStringResource {
        resource("logging.session.plan.reps-delta \(reps)")
    }

    // MARK: - Adherence (FR-15.3.3)

    /// The label on the workout's adherence, among its own facts.
    static let sessionAdherence = resource("logging.session.adherence")

    /// How much of the plan was performed as prescribed, as a count over a count.
    ///
    /// **Plural on the total, in the `.stringsdict`**, for
    /// ``LoggingStrings/sessionProgress(completed:total:)``'s reason — the noun is the one the total
    /// agrees with.
    ///
    /// - Parameters:
    ///   - asPrescribed: How many prescribed sets were completed as planned.
    ///   - prescribed: How many were prescribed.
    /// - Returns: The reading.
    static func sessionAdherenceValue(
        asPrescribed: Int, prescribed: Int
    ) -> LocalizedStringResource {
        resource("logging.session.adherence \(asPrescribed) \(prescribed)")
    }

    // MARK: - A load as a share of the training max (FR-16.7.1)

    /// A load read against the training max in force on the session's day.
    ///
    /// **`TM` rather than the words, and that is the requirement's own spelling.** It sits under a
    /// load on a row already spending its width on two 44pt controls; "of the training max" at
    /// `NFR-1.10`'s ceiling takes three lines to say what the reader already knows they are looking
    /// at.
    ///
    /// **The percentage arrives already rendered**, on ``sessionPlanTarget(weight:reps:)``'s rule:
    /// a number formatted here would be formatted twice, and the symbol's place is the locale's.
    ///
    /// - Parameter percentage: The share, rendered for the reader.
    /// - Returns: The annotation.
    static func setTrainingMaxShare(_ percentage: String) -> LocalizedStringResource {
        resource("logging.set.training-max-share \(percentage)")
    }

    /// This surface's copy, for ``LoggingStrings/all``.
    static var allPlanStrings: [LocalizedStringResource] {
        [
            setTrainingMaxShare("88%"),
            sessionExerciseMarkedDone, sessionExerciseSkipped,
            sessionPlanNextHeading, sessionPlanLogAction, sessionPlanOnTarget,
            sessionPlanTarget(weight: "", reps: 0),
            sessionPlanTargetOpenLoad(reps: 0),
            sessionPlanRepsDelta(0),
            sessionAdherence,
            sessionAdherenceValue(asPrescribed: 0, prescribed: 0),
            sessionAdherenceValue(asPrescribed: 1, prescribed: 1),
        ] + [true, false].map(sessionExerciseDoneAction(isDone:))
    }
}
