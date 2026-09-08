import Foundation

/// ``LoggingStrings``' tenth file — `FR-17.1`'s Log sheet: the group form's own fields, the
/// Planned / Actual pair, the per-set fold and the two actions.
///
/// The same type in another file, on `LoggingDayStrings.swift`'s argument.
extension LoggingStrings {
    // MARK: - The sheet (FR-17.1.6, FR-17.9.4)

    /// The line under the sheet's heading, which is the whole of what it asks.
    static let setEditorQuestion = resource("logging.session.set.editor.question")

    /// How many sets of it the lifter did (`FR-17.1.1`).
    static let setSetsLabel = resource("logging.session.set.sets.label")

    /// The ± pair's spoken labels — never the drawn form, which is a glyph (T-16.01).
    static let setSetsIncrease = resource("logging.session.set.sets.increase")

    /// The other half of it.
    static let setSetsDecrease = resource("logging.session.set.sets.decrease")

    /// The left half of the pair under the fields.
    static let setPlannedLabel = resource("logging.session.set.planned.label")

    /// The right half of it.
    static let setActualLabel = resource("logging.session.set.actual.label")

    /// The fold holding warm-ups, RPE, notes, modifiers and per-set reps (`FR-17.9.4`).
    static let setDetailsLabel = resource("logging.session.set.details.label")

    /// What the sheet's primary command reads — it answers the row *and* marks it done.
    static let setSaveDoneAction = resource("logging.session.set.save-done.action")

    // MARK: - The deviation sentence (FR-17.9.4)

    /// The actual group with what it did against the plan appended.
    ///
    /// - Parameters:
    ///   - performed: What was done, rendered.
    ///   - deviation: The sentence.
    /// - Returns: `30 × 8 × 3 · −2 reps`.
    static func setDeviationLine(performed: String, deviation: String) -> LocalizedStringResource {
        resource("logging.session.set.deviation.line \(performed) \(deviation)")
    }

    /// The load's clause, already signed by ``DesignSystem/DeltaDirection/sign``.
    ///
    /// - Parameter weight: The signed magnitude, rendered in the lifter's unit.
    /// - Returns: The clause.
    static func setDeviationWeight(_ weight: String) -> LocalizedStringResource {
        resource("logging.session.set.deviation.weight \(weight)")
    }

    /// The repetitions' clause. Plural on the count, so one rep does not read *1 reps*.
    ///
    /// - Parameters:
    ///   - sign: The direction's sign.
    ///   - count: How many, unsigned.
    /// - Returns: The clause.
    static func setDeviationReps(sign: String, count: Int) -> LocalizedStringResource {
        resource("logging.session.set.deviation.reps \(sign) \(count)")
    }

    /// The set count's clause, on ``setDeviationReps(sign:count:)``'s rule.
    ///
    /// - Parameters:
    ///   - sign: The direction's sign.
    ///   - count: How many, unsigned.
    /// - Returns: The clause.
    static func setDeviationSets(sign: String, count: Int) -> LocalizedStringResource {
        resource("logging.session.set.deviation.sets \(sign) \(count)")
    }

    /// What a group that hit everything the plan named says.
    static let setDeviationAsPlanned = resource("logging.session.set.deviation.as-planned")

    /// What separates two clauses. A string rather than a comma, `G-3.4`.
    static let setDeviationSeparator = resource("logging.session.set.deviation.separator")

    /// Every string this file declares, for the test that renders them all.
    static var allLogSheetStrings: [LocalizedStringResource] {
        [
            setEditorQuestion,
            setSetsLabel,
            setSetsIncrease,
            setSetsDecrease,
            setPlannedLabel,
            setActualLabel,
            setDetailsLabel,
            setSaveDoneAction,
            setDeviationLine(performed: "30 kg × 8 × 3", deviation: "−2 reps"),
            setDeviationWeight("+2.5 kg"),
            setDeviationReps(sign: "−", count: 2),
            setDeviationReps(sign: "−", count: 1),
            setDeviationSets(sign: "+", count: 1),
            setDeviationSets(sign: "+", count: 2),
            setDeviationAsPlanned,
            setDeviationSeparator,
        ]
    }
}
