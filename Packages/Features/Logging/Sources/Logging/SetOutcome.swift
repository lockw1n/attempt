import DesignSystem
import RepositoryInterface

/// What the mark at the end of a set row reports (`FR-1.2.5`, `FR-16.4.1`).
///
/// **Three states from two stored columns, and no third column.** `isCompleted` is a schema-v1
/// Boolean that cannot be backfilled (`G-1.8`), so *pending* is derived: an uncompleted set inside a
/// session that has not ended. A finished session is two-valued exactly as every reader of it
/// assumes, and the same row read after Finish is a failed set.
///
/// **A set nobody attempted is not a missed lift.** Red is reserved for failure (`G-7.3`), so
/// pending takes the tertiary ramp; and the three glyphs differ in shape rather than only in tint,
/// which is `G-4.5` — a hollow circle is legible as "nothing happened here" in a monochrome
/// rendering.
enum SetOutcome: Equatable, Sendable {
    /// The set was performed.
    case completed

    /// It was attempted and missed.
    case failed

    /// Nobody has attempted it yet.
    case pending

    /// Which of the three a set is.
    ///
    /// - Parameters:
    ///   - isCompleted: The set's own column.
    ///   - isSessionOpen: Whether the session holding it has yet to end.
    /// - Returns: The outcome to draw.
    static func of(isCompleted: Bool, isSessionOpen: Bool) -> Self {
        if isCompleted { return .completed }
        return isSessionOpen ? .pending : .failed
    }

    /// The SF Symbol drawn for it.
    var glyph: String {
        switch self {
        case .completed: "checkmark.circle"
        case .failed: "xmark.circle"
        case .pending: "circle"
        }
    }

    /// Its place in the colour ramp.
    ///
    /// **Only failure is coloured.** Every set logged on the screen is completed, so a green tick
    /// per row would be a colour to look past on the way to the one row that differs.
    var tint: ColorToken {
        self == .failed ? ColorToken.negative : ColorToken.textTertiary
    }

    /// Where the load and the repetitions sit in that ramp.
    ///
    /// **A failed set is red wherever it sits** (`G-7.3` names "failure and missed lifts"), so the
    /// outcome outranks the warmup de-emphasis rather than compounding with it — a failed warmup is
    /// a missed lift too. A pending one is quieter still than a warmup: nothing has happened yet.
    ///
    /// - Parameter isWarmup: Whether the set is a warmup rather than working.
    /// - Returns: The colour its numbers take.
    func valueColour(isWarmup: Bool) -> ColorToken {
        switch self {
        case .failed: ColorToken.negative
        case .pending: ColorToken.textTertiary
        case .completed: isWarmup ? ColorToken.textSecondary : ColorToken.textPrimary
        }
    }
}
