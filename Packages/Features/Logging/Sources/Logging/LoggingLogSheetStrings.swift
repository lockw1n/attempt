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

    // MARK: - The sections (FR-18.6.2, FR-18.6.4)

    /// What names a group on a sheet that draws more than one (`FR-18.6.2`).
    ///
    /// - Parameter number: Its position in the plan, counting from one.
    /// - Returns: The heading.
    static func setGroupHeading(_ number: Int) -> LocalizedStringResource {
        resource("logging.session.set.group.heading \(number)")
    }

    /// What a section at zero sets says where the group it was done against is rendered
    /// (`FR-18.6.5`, `G-4.5`) — in words, never as `× 0`.
    static let setGroupNotDone = resource("logging.session.set.group.not-done")

    /// The line under the sections when every one of them is at zero (`Q-18.7`).
    ///
    /// **Says *below* because the command it names is pinned directly beneath it** — which is true
    /// at every size ``SetEditorRoom`` leaves the skip in the footer, and at no other. See
    /// ``setEveryGroupEmptyHintInForm``.
    static let setEveryGroupEmptyHint = resource("logging.session.set.group.every-empty.hint")

    /// The same line where ``SetEditorRoom`` has moved **Skip this exercise** into the scrolling
    /// form (`FR-18.6.9`).
    ///
    /// **A second key rather than one direction-free wording**, so that the sizes where the
    /// command *is* directly beneath the line keep being told so — and so that nothing drawn at the
    /// default type size moves for this, which is `T-18.21`'s own constraint. This is also the one
    /// state the hint exists for: it is drawn only while nothing can be saved, which is exactly
    /// when the lifter is looking for the command it names.
    static let setEveryGroupEmptyHintInForm = resource(
        "logging.session.set.group.every-empty.hint.in-form")

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
            setGroupHeading(1),
            setGroupHeading(2),
            setGroupNotDone,
            setEveryGroupEmptyHint,
            setEveryGroupEmptyHintInForm,
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
