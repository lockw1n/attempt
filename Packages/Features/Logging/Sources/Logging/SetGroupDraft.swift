import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface

/// What one set of a group carries when it differs from the form above it (`FR-17.9.4`).
///
/// **The four optional fields plus the reps, and deliberately not the load.** A different load is a
/// different group — the Log sheet answers *what did you do* for one prescription, and a lifter who
/// dropped the weight for the last two sets logs that as a second answer rather than as a column
/// here. Reps are the one required field that varies inside a run the lifter still thinks of as one
/// exercise: `80 × 8, 8, 6`.
///
/// **It carries its own locale**, like ``SetDraft``, because it holds text rather than numbers and
/// the crossing back is `LocalizedNumberField`'s.
struct SetDetailDraft: Equatable, Sendable {
    /// The locale both numeric fields are read in.
    let locale: Locale

    /// The repetitions for this set, as typed.
    var repsText: String = ""

    /// The RPE for this set, as typed. Optional (`FR-1.2.3`).
    var rpeText: String = ""

    /// Whether this set was a warmup rather than working (`FR-1.2.4`).
    var isWarmup: Bool = false

    /// The note on this set (`FR-1.2.3`).
    var notes: String = ""

    /// The modifiers this set was performed under (`FR-1.2.8`).
    var modifiers: [SetModifier] = []

    /// The repetitions, or `nil` where the field does not hold a count.
    var reps: Int? { LocalizedNumberField.count(repsText, locale: locale) }

    /// The rating, whether it was skipped, or whether what is there is not one — ``SetDraft``'s
    /// rule, read from its one home.
    var rpe: OptionalField<Double> { SetDraft.rating(rpeText, locale: locale) }

    /// Whether this set can be written.
    var isResolvable: Bool { reps != nil && rpe != .invalid }

    /// The rating to store, once ``isResolvable`` is known to hold.
    var storedRPE: Double? {
        if case .value(let rating) = rpe { return rating }
        return nil
    }
}

/// What the Log sheet resolves to — the form's own answer, how many sets of it, and the rows that
/// will actually be written (`FR-17.1.1`, `NFR-17.3`).
///
/// **Three fields rather than just the rows, and each has a caller.** ``values`` is what the form
/// says and is what the Planned / Actual pair is measured from; ``sets`` is the count that pair
/// reports; ``rows`` is what the store writes, which differs from N copies of ``values`` exactly
/// when the per-set fold was used.
struct ResolvedSetGroup: Equatable, Sendable {
    /// What the form itself says — the load, the reps, and the optional fields as typed above the
    /// fold.
    let values: SetEntryValues

    /// How many sets of it. At least one.
    let sets: Int

    /// The rows to write, in order — ``sets`` of them.
    let rows: [SetEntryValues]
}

// MARK: - The group the draft resolves to

extension SetDraft {
    /// How many sets the form asks for, or `nil` where the field does not hold a count of at least
    /// one.
    ///
    /// **Zero is refused rather than floored here.** ``adjustingSets(by:)`` floors the ± pair, but
    /// a lifter who typed `0` has said something the sheet cannot write — a group of no sets is the
    /// row left unanswered, and **Skip this exercise** is how that is said.
    var sets: Int? {
        guard let count = LocalizedNumberField.count(setsText, locale: locale), count >= 1 else {
            return nil
        }
        return count
    }

    /// This draft with its set count moved by `steps`, floored at one. See ``adjustingWeight(by:)``.
    ///
    /// - Parameter steps: How many sets to move — negative is down.
    /// - Returns: The adjusted draft.
    func adjustingSets(by steps: Int) -> SetDraft {
        var adjusted = self
        let moved = max(1, (sets ?? 1) + steps)
        adjusted.setsText = LocalizedNumberField.render(Double(moved), locale: locale)
        adjusted.details = Self.details(of: adjusted, count: adjusted.details.isEmpty ? 0 : moved)
        return adjusted
    }

    /// One entry per set, filled in from the form's own fields (`FR-17.9.4`).
    ///
    /// **Prefilled rather than blank**, which is what makes the fold an *override*: a lifter who
    /// opens it to change the last set's reps must not have to retype the first two.
    ///
    /// - Parameters:
    ///   - draft: The form to read.
    ///   - count: How many entries to build. Zero returns none, which is the closed fold.
    /// - Returns: The entries.
    static func details(of draft: SetDraft, count: Int) -> [SetDetailDraft] {
        guard count > 0 else { return [] }
        return (0..<count).map { _ in
            SetDetailDraft(
                locale: draft.locale,
                repsText: draft.repsText,
                rpeText: draft.rpeText,
                isWarmup: draft.isWarmup,
                notes: draft.notes,
                modifiers: draft.modifiers)
        }
    }

    /// This draft with the fold opened — one entry per set, prefilled.
    ///
    /// - Returns: The draft.
    func openingDetails() -> SetDraft {
        var opened = self
        opened.details = Self.details(of: self, count: sets ?? 1)
        return opened
    }

    /// This draft with the fold closed and its entries discarded.
    ///
    /// - Returns: The draft.
    func closingDetails() -> SetDraft {
        var closed = self
        closed.details = []
        return closed
    }

    /// This draft with its per-set entries rebuilt from the form (`FR-17.9.4`).
    ///
    /// **A reset rather than a merge, and only while the fold is open.** The entries are the form's
    /// numbers as overrides; once the form's reps or set count move, an entry kept from before is a
    /// number the lifter changed and the sheet ignored. A closed fold has nothing to rebuild, so
    /// this answers itself — which is what keeps the rule off every keystroke on a free workout.
    ///
    /// - Returns: The draft.
    func resettingDetails() -> SetDraft {
        guard !details.isEmpty else { return self }
        return openingDetails()
    }

    /// What this draft writes — the form's answer, the count, and one row per set
    /// (`FR-17.1.1`, `NFR-17.3`).
    ///
    /// **The rows are the fold's when it is open and N copies of the form's when it is not**, and
    /// the two must agree on everything the fold did not touch: a row built from an entry takes the
    /// group's load, because a different load is a different group.
    ///
    /// `nil` where the draft does not resolve, on ``resolved``'s rule — and that single guard is
    /// also what makes ``ResolvedSetGroup/rows`` exactly ``ResolvedSetGroup/sets`` long: ``resolved``
    /// requires ``isLoggable``, which requires every entry of ``details`` to resolve, and the
    /// rebuilt branch copies text that same check has already read. A second count guard here
    /// would be a branch no test can reach.
    var resolvedGroup: ResolvedSetGroup? {
        guard let values = resolved, let sets else { return nil }
        let entries = details.count == sets ? details : Self.details(of: self, count: sets)
        return ResolvedSetGroup(
            values: values, sets: sets, rows: entries.compactMap { Self.row(values, applying: $0) })
    }

    /// One row, the group's load with one set's own answers over it.
    ///
    /// - Parameters:
    ///   - values: What the form says.
    ///   - detail: What this set says instead.
    /// - Returns: The row, or `nil` where the entry does not resolve.
    static func row(_ values: SetEntryValues, applying detail: SetDetailDraft) -> SetEntryValues? {
        guard let reps = detail.reps, detail.rpe != .invalid else { return nil }
        return SetEntryValues(
            weight: values.weight,
            reps: reps,
            rpe: detail.storedRPE,
            isWarmup: detail.isWarmup,
            modifiers: detail.modifiers,
            notes: detail.notes)
    }
}

// MARK: - What a checklist row's form opens holding

extension SetDraft {
    /// A draft filled in for a day's checklist row (`FR-17.9.4`, `FR-17.7.5`).
    ///
    /// **Two prefills, and which one runs is whether the row has been answered.** An unanswered row
    /// fills in from the plan — the collapsed first group, load, reps and its set count — so the
    /// commonest save is *open, save*. An answered one fills in from what is actually stored,
    /// because the save it leads to is a rewrite of those rows and a form that opened on the plan
    /// would quietly undo the deviation the lifter came back to correct.
    ///
    /// **The fold opens only where the stored sets disagree with each other.** A row of five
    /// identical sets is said by the form above the fold; one logged `8, 8, 6` cannot be, and
    /// opening it prefilled is the only way that answer survives a reopen.
    ///
    /// - Parameters:
    ///   - row: The checklist row.
    ///   - unit: The unit to render the load in.
    ///   - locale: The locale to render the numbers in.
    init(answering row: SetEditorRow, unit: MassUnit, locale: Locale) {
        self.init(unit: unit, locale: locale)
        if let first = row.logged.first {
            weightText = LocalizedNumberField.render(first.weight, in: unit, locale: locale)
            repsText = LocalizedNumberField.render(Double(first.reps), locale: locale)
            setsText = LocalizedNumberField.render(Double(row.logged.count), locale: locale)
            if let rpe = first.rpe {
                rpeText = LocalizedNumberField.render(rpe, locale: locale)
            }
            isWarmup = first.isWarmup
            modifiers = first.modifiers
            notes = first.notes
            if !Self.isUniform(row.logged) {
                details = Self.details(of: row.logged, locale: locale)
            }
            return
        }
        guard let group = DayPerformance.collapsed(row.plan).first else { return }
        if let weight = group.weight {
            weightText = LocalizedNumberField.render(weight, in: unit, locale: locale)
        }
        repsText = LocalizedNumberField.render(Double(group.reps), locale: locale)
        setsText = LocalizedNumberField.render(Double(group.sets), locale: locale)
    }

    /// Whether every stored set says the same thing about everything except its load.
    ///
    /// **The load is deliberately not compared.** It is the group's, and a set at a different load
    /// is a different group — the fold cannot express one, so opening it would not help.
    ///
    /// - Parameter logged: The stored sets, in order.
    /// - Returns: Whether the form above the fold can say all of them.
    static func isUniform(_ logged: [SetEntry]) -> Bool {
        guard let first = logged.first else { return true }
        return logged.allSatisfy {
            $0.reps == first.reps && $0.rpe == first.rpe && $0.isWarmup == first.isWarmup
                && $0.notes == first.notes && $0.modifiers == first.modifiers
        }
    }

    /// One entry per stored set, filled in from it (`FR-17.7.5`).
    ///
    /// - Parameters:
    ///   - logged: The stored sets, in order.
    ///   - locale: The locale the numbers are rendered in.
    /// - Returns: The entries.
    static func details(of logged: [SetEntry], locale: Locale) -> [SetDetailDraft] {
        logged.map { set in
            SetDetailDraft(
                locale: locale,
                repsText: LocalizedNumberField.render(Double(set.reps), locale: locale),
                rpeText: set.rpe.map { LocalizedNumberField.render($0, locale: locale) } ?? "",
                isWarmup: set.isWarmup,
                notes: set.notes,
                modifiers: set.modifiers)
        }
    }
}
