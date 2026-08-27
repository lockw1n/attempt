import DerivedValues
import Foundation
import PowerliftingCore

/// `FR-1.7`'s copy: the estimate, what produced it, and the seven reasons there is none.
///
/// A file of its own rather than more of ``ExerciseLibraryStrings``, which had reached SwiftLint's
/// length ceiling. Same type, same catalogue, same key convention.
extension ExerciseLibraryStrings {
    /// The estimate's own label, beside the number.
    static let e1rmValue = resource("exerciselibrary.detail.e1rm.value")

    /// The estimate could not be computed — a read failed, which a retry may fix.
    static let e1rmError = resource("exerciselibrary.detail.e1rm.error")

    /// How the estimate was produced: the formula, and the window it read.
    ///
    /// **The name arrives already resolved**, on ``historyRPE(_:)``'s rule: a
    /// `LocalizedStringResource` interpolated into another is not a `%@` argument.
    ///
    /// - Parameters:
    ///   - formula: The formula's name, resolved for the locale.
    ///   - days: How many days back the estimate looked.
    /// - Returns: The footnote.
    static func e1rmProvenance(_ formula: String, days: Int) -> LocalizedStringResource {
        resource("exerciselibrary.detail.e1rm.provenance \(formula) \(days)")
    }

    /// Why a lifter who *has* logged sets still sees no estimate (`FR-1.13.3`).
    ///
    /// **Seven sentences and not one**, this screen's half of the answer to `E1RMCalculator`'s silent
    /// refusals: each names the thing that would have to change. One sentence covering all of them
    /// would have to be "no estimate", which is the blank it replaces.
    ///
    /// - Parameters:
    ///   - absence: Why the estimate is missing.
    ///   - days: The window's length — "no recent set" means something different at thirty days
    ///     than at ninety, so every in-window sentence names it.
    /// - Returns: The sentence.
    static func e1rmAbsence(_ absence: EstimateAbsence, days: Int) -> LocalizedStringResource {
        switch absence {
        case .noSetsLogged: e1rmNone
        case .noneInWindow: resource("exerciselibrary.detail.e1rm.stale \(days)")
        case .refused(.warmup): resource("exerciselibrary.detail.e1rm.warmups \(days)")
        case .refused(.incomplete): resource("exerciselibrary.detail.e1rm.incomplete \(days)")
        case .refused(.assisted): resource("exerciselibrary.detail.e1rm.assisted")
        case .refused(.repsOutOfRange):
            resource("exerciselibrary.detail.e1rm.high-reps \(days)")
        case .refused(.formulaDeclined): resource("exerciselibrary.detail.e1rm.no-effort")
        }
    }

    /// A formula's name, as a lifter would see it cited (`FR-1.7.2`).
    ///
    /// Five surnames and one description, owned here for the reason every other vocabulary in this
    /// file is: a string declared in a package resolves against that package's bundle.
    ///
    /// - Parameter formula: The formula to name.
    /// - Returns: Its name.
    static func name(for formula: E1RMFormulaID) -> LocalizedStringResource {
        switch formula {
        case .epley: resource("exerciselibrary.detail.e1rm.formula.epley")
        case .brzycki: resource("exerciselibrary.detail.e1rm.formula.brzycki")
        case .lombardi: resource("exerciselibrary.detail.e1rm.formula.lombardi")
        case .oConner: resource("exerciselibrary.detail.e1rm.formula.oconner")
        case .wathan: resource("exerciselibrary.detail.e1rm.formula.wathan")
        case .rpeBased: resource("exerciselibrary.detail.e1rm.formula.rpebased")
        }
    }

    /// What tapping the estimate does, as VoiceOver reads it (`G-4.2`, `FR-1.7.4`).
    ///
    /// Not ``ExerciseLibraryStrings/recordsSourceHint``: that one says "this record", and an
    /// estimate is not a record — it is a number computed *from* a set.
    static let e1rmSourceHint = resource("exerciselibrary.detail.e1rm.source-hint")

    /// `FR-1.7.5`'s "clearly marked as manual", in place of the provenance line — a manual number
    /// has no formula and no window behind it.
    static let e1rmManualBadge = resource("exerciselibrary.detail.e1rm.manual")

    /// The command that opens the override field.
    static let e1rmOverrideAction = resource("exerciselibrary.detail.e1rm.override.action")

    /// The override field's own name, which is also its placeholder.
    static let e1rmOverrideField = resource("exerciselibrary.detail.e1rm.override.field")

    /// Commits what was typed.
    static let e1rmOverrideSave = resource("exerciselibrary.detail.e1rm.override.save")

    /// Abandons it, leaving whatever was in force.
    static let e1rmOverrideCancel = resource("exerciselibrary.detail.e1rm.override.cancel")

    /// `FR-1.7.5`'s way back: one tap, and the computed estimate returns.
    static let e1rmOverrideRevert = resource("exerciselibrary.detail.e1rm.override.revert")

    /// The override could not be stored. Nothing changed, so the retry is the same command.
    static let e1rmOverrideError = resource("exerciselibrary.detail.e1rm.override.error")

    /// Every reason an estimate can be missing, so ``ExerciseLibraryStrings/all`` covers each
    /// sentence. Internal because the list it feeds lives in the other file.
    static var absences: [EstimateAbsence] {
        [.noSetsLogged, .noneInWindow] + E1RMRefusal.allCases.map(EstimateAbsence.refused)
    }
}
