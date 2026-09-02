import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface

/// One target weight/rep/set group as the editor holds it (`FR-15.2.1`'s amendment).
///
/// **Text, not numbers**, and every crossing back into one is
/// ``Localization/LocalizedNumberField``'s — `Logging`'s `SetDraft` argues that rule and the locale
/// it is read in, and this is the same crossing over a plan rather than over a performance.
///
/// **An empty ``weightText`` is `FR-15.2.2`'s blank target and not a refusal.** It is the one field
/// here that may be left alone; reps and sets are prescribed whether or not a weight is known
/// (`FR-15.2.1`), so a group missing either of those is a group that will not save.
struct RoutineGroupDraft: Identifiable, Equatable {
    /// The stored group's identifier, minted once when the row is added.
    ///
    /// **Once, not per save**, for `ExerciseFormState.newExerciseID`'s reason: a write that failed
    /// may still have landed, and a retry that minted a second identifier would fork the row.
    let id: UUID

    /// The load, as typed. Empty is a blank target (`FR-15.2.2`).
    var weightText: String = ""

    /// The repetitions prescribed per set, as typed.
    var repsText: String = ""

    /// The sets prescribed, as typed.
    var setsText: String = ""

    /// An empty group, ready to be filled in.
    init(id: UUID = UUID()) {
        self.id = id
    }

    /// The group as the store holds it, rendered back into the editor's fields.
    ///
    /// - Parameters:
    ///   - group: The stored group.
    ///   - unit: The unit to render the load in.
    ///   - locale: The locale to render the numbers in.
    init(_ group: RoutineTargetGroup, unit: MassUnit, locale: Locale) {
        id = group.id
        // A blank stored target renders as an empty field, which is the same thing the editor
        // means by one — the round trip `FR-15.2.2` needs.
        weightText =
            group.targetWeight.map { LocalizedNumberField.render($0, in: unit, locale: locale) }
            ?? ""
        repsText = LocalizedNumberField.render(Double(group.targetReps), locale: locale)
        setsText = LocalizedNumberField.render(Double(group.targetSets), locale: locale)
    }
}

/// One exercise slot as the editor holds it, with its groups in order.
struct RoutineSlotDraft: Identifiable, Equatable {
    /// The stored slot's identifier, minted once. See ``RoutineGroupDraft/id``.
    let id: UUID

    /// The catalogue exercise this slot prescribes.
    let exerciseID: UUID

    /// The name drawn on the row, resolved for the reader's locale when the slot was built
    /// (`FR-1.14.2`).
    ///
    /// **Carried rather than looked up per draw**, because the editor holds a draft and the
    /// catalogue read that produced this name happened once. It is display only: what is stored is
    /// ``exerciseID``.
    var name: String

    /// The target groups, in the order they are drawn and stored.
    var groups: [RoutineGroupDraft]
}

// MARK: - What a draft resolves to

extension RoutineGroupDraft {
    /// The load, `nil` for a blank target — and there is no third answer here, which is why
    /// ``isResolvable(unit:locale:)`` reads ``weightText`` separately.
    func weight(unit: MassUnit, locale: Locale) -> Weight? {
        LocalizedNumberField.weight(weightText, in: unit, locale: locale)
    }

    /// Whether the load field is empty, which is `FR-15.2.2`'s blank target.
    var isBlankWeight: Bool {
        weightText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The prescribed repetitions, or `nil` where the field does not hold a positive count.
    func reps(locale: Locale) -> Int? {
        positive(repsText, locale: locale)
    }

    /// The prescribed sets, or `nil` where the field does not hold a positive count.
    func sets(locale: Locale) -> Int? {
        positive(setsText, locale: locale)
    }

    /// Whether this group can be stored: reps and sets prescribed, and a load that is either blank
    /// or a number.
    ///
    /// **Blank passes and unparseable does not**, which is the distinction the type's own note
    /// makes: `weight(unit:locale:)` answers `nil` to both, so reading it alone would store a
    /// mistyped load as a deliberately blank one.
    func isResolvable(unit: MassUnit, locale: Locale) -> Bool {
        guard reps(locale: locale) != nil, sets(locale: locale) != nil else { return false }
        return isBlankWeight || weight(unit: unit, locale: locale) != nil
    }

    /// A count that is a whole number greater than zero, or `nil`.
    ///
    /// Zero is refused here where `Logging`'s set draft accepts it: a *logged* set of zero reps is
    /// `FR-1.2.5`'s failed set, and a *prescribed* zero is a plan to do nothing.
    private func positive(_ text: String, locale: Locale) -> Int? {
        guard let value = LocalizedNumberField.count(text, locale: locale), value > 0 else {
            return nil
        }
        return value
    }
}
