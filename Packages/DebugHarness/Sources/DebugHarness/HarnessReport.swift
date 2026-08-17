import PowerliftingCore
import SeedImport

/// What one run produced (`DOD-0.3`).
///
/// A value rather than printed output, so the assertions live on the numbers and only ``text``
/// depends on the layout.
public struct HarnessReport: Sendable, Equatable {
    /// One set as it came back out of storage, with what the estimator made of it.
    public struct LoggedSet: Sendable, Equatable {
        /// The load lifted, on one implement.
        public let weight: Weight

        /// Reps performed.
        public let reps: Int

        /// The rated effort, or `nil` where none was recorded.
        public let rpe: Double?

        /// Whether this was a warmup.
        public let isWarmup: Bool

        /// Whether the set was completed.
        public let isCompleted: Bool

        /// The estimated one-rep maximum, or `nil` where ``PowerliftingCore/E1RMCalculator``
        /// refused the set or the formula declined it.
        public let estimate: Weight?

        /// Creates one line of the log.
        public init(
            weight: Weight,
            reps: Int,
            rpe: Double?,
            isWarmup: Bool,
            isCompleted: Bool,
            estimate: Weight?
        ) {
            self.weight = weight
            self.reps = reps
            self.rpe = rpe
            self.isWarmup = isWarmup
            self.isCompleted = isCompleted
            self.estimate = estimate
        }
    }

    /// What the seed import did. A second run over the same store writes nothing.
    public let seed: SeedImportSummary

    /// The catalogue name the history was logged against.
    public let exerciseName: String

    /// The estimator the records were computed under.
    public let formula: E1RMFormulaID

    /// The sets as stored, oldest first — the collection a ``PowerliftingCore/PersonalRecord``'s
    /// offset indexes into.
    public let sets: [LoggedSet]

    /// The records those sets hold.
    public let records: PersonalRecords

    /// Creates a report.
    public init(
        seed: SeedImportSummary,
        exerciseName: String,
        formula: E1RMFormulaID,
        sets: [LoggedSet],
        records: PersonalRecords
    ) {
        self.seed = seed
        self.exerciseName = exerciseName
        self.formula = formula
        self.sets = sets
        self.records = records
    }

    /// The whole report as one printable block, unlocalised (`OUT-0.1` ships no user-facing text).
    public var text: String {
        (header + [""] + setLines + [""] + recordLines)
            .map(Self.trimmingTrailingSpaces)
            .joined(separator: "\n")
    }

    /// What ran, against what.
    private var header: [String] {
        [
            "Attempt debug harness — DOD-0.3",
            "exercise   \(exerciseName)",
            "formula    \(formula.rawValue)",
            "seed       \(seed.inserted) inserted, \(seed.updated) updated, "
                + "\(seed.archived) archived, \(seed.unchanged) unchanged "
                + "— \(seed.writeCount) write(s)",
        ]
    }

    /// One line per stored set, in storage order.
    private var setLines: [String] {
        ["sets, oldest first"]
            + sets.enumerated().map { offset, set in
                let load = Self.rightAligned(set.weight.formatted(in: .kilograms), width: 6)
                let reps = Self.leftAligned("\(set.reps)", width: 2)
                let effort = set.rpe.map { "RPE \(Self.trimmed($0))" } ?? ""
                let flag = set.isWarmup ? "warmup" : (set.isCompleted ? "" : "incomplete")
                return "  [\(offset)] \(load) kg × \(reps)  "
                    + Self.leftAligned(effort, width: 9)
                    + Self.leftAligned(flag, width: 11)
                    + "e1RM \(Self.mass(set.estimate))"
            }
    }

    /// Every N in `PersonalRecords.repRange`, present or not, then the best estimate.
    private var recordLines: [String] {
        ["rep maxes"]
            + PersonalRecords.repRange.map { reps in
                let record = records.repMax(forReps: reps)
                return "  \(Self.rightAligned("\(reps)", width: 2))RM  "
                    + Self.leftAligned(Self.mass(record?.weight), width: 22)
                    + (record.map { "from set [\($0.setOffset)]" } ?? "")
            }
            + [
                "",
                "best e1RM  " + Self.leftAligned(Self.mass(records.bestE1RM?.weight), width: 22)
                    + (records.bestE1RM.map { "from set [\($0.setOffset)]" } ?? ""),
            ]
    }

    /// Kilograms at display precision beside the stored grams — `G-3.3` and `G-1.1` in one string,
    /// which is the pair a harness exists to show. `—` where there is no answer.
    private static func mass(_ weight: Weight?) -> String {
        guard let weight else { return "—" }
        return "\(weight.formatted(in: .kilograms)) kg (\(weight.description))"
    }

    /// An RPE without its trailing zero — `8` rather than `8.0`, `8.5` unchanged.
    private static func trimmed(_ rpe: Double) -> String {
        let halves = Int((rpe * 2).rounded())
        return halves.isMultiple(of: 2) ? "\(halves / 2)" : "\(Double(halves) / 2)"
    }

    /// `line` without the padding a column of `—` would otherwise leave hanging off the end.
    private static func trimmingTrailingSpaces(_ line: String) -> String {
        var trimmed = line
        while trimmed.hasSuffix(" ") { trimmed.removeLast() }
        return trimmed
    }

    /// `text` padded on the left to `width`, or unchanged when it is already wider.
    private static func rightAligned(_ text: String, width: Int) -> String {
        String(repeating: " ", count: max(0, width - text.count)) + text
    }

    /// `text` padded on the right to `width`, or unchanged when it is already wider.
    private static func leftAligned(_ text: String, width: Int) -> String {
        text + String(repeating: " ", count: max(0, width - text.count))
    }
}
