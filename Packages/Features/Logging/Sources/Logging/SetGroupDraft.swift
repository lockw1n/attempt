import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface

/// What one set of a group carries when it differs from the form above it (`FR-17.9.4`).
///
/// **The four optional fields plus the reps, and no load the lifter can type.** A different load is
/// a different group — the Log sheet answers *what did you do* for one prescription, and a lifter
/// who dropped the weight for the last two sets logs that as a second answer rather than as a
/// column here. Reps are the one required field that varies inside a run the lifter still thinks of
/// as one exercise: `80 × 8, 8, 6`. ``storedWeight`` is the exception that proves the rule: a load
/// carried across a rewrite, never a field.
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

    /// The load this set is stored at, where that is not the load the form above the fold says
    /// (`FR-18.6.8`).
    ///
    /// **Carried, never edited.** There is no per-set load field and this phase is not adding one
    /// (`OUT-18.16`): a *working* set at another load is another group, and the sections give it a
    /// form of its own. What is left is the warm-up, which is placed by position rather than by
    /// load and can therefore sit inside a group at a lighter one — an imported session
    /// (`FR-16.4`) or a free workout logs every set on its own form. Filled in only by
    /// ``SetDraft/details(of:at:locale:)``, so a set added in the sheet carries none.
    ///
    /// **`nil` means "the group's load", not "no load"** — and it is what a warm-up stored *at*
    /// the group's load holds, so that one still follows an edit of the load field (`Q-18.11`).
    var storedWeight: Weight?

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
/// says and is what the Planned / Actual pair is measured from; ``sets`` is every set of the
/// group, which is what the form's own count field holds; ``rows`` is what the store writes, which
/// differs from N copies of ``values`` exactly when the per-set fold was used.
struct ResolvedSetGroup: Equatable, Sendable {
    /// What the form itself says — the load, the reps, and the optional fields as typed above the
    /// fold.
    let values: SetEntryValues

    /// How many sets of it, warm-ups included. At least one.
    let sets: Int

    /// The rows to write, in order — ``sets`` of them.
    let rows: [SetEntryValues]

    /// How many of ``rows`` are work, or ``sets`` where none of them are (`FR-18.6.5`).
    ///
    /// **What the Planned / Actual pair counts, because a plan prescribes work.** ``sets`` has to
    /// be every set — the rewrite is positional — so a group of `1 warm-up + 3 working` reads four
    /// there, and a line saying `100 kg × 5 × 4` against a plan of `× 3` calls out a deviation the
    /// lifter did not make. A group of warm-ups alone falls back to ``sets``: `× 0` reads as a
    /// number they entered (`G-4.5`).
    var workingSets: Int {
        let working = rows.filter { !$0.isWarmup }.count
        return working == 0 ? sets : working
    }
}

// MARK: - The group the draft resolves to

extension SetDraft {
    /// How many sets the form asks for, or `nil` where the field does not hold a count of at least
    /// ``minimumSets``.
    ///
    /// **Zero is refused rather than floored here, on a form whose floor is one.**
    /// ``adjustingSets(by:)`` floors the ± pair, but a lifter who typed `0` there has said
    /// something the sheet cannot write — a group of no sets is the row left unanswered, and
    /// **Skip this exercise** is how that is said.
    ///
    /// **In a sheet with several sections the floor is zero and `0` is an answer**
    /// (`FR-18.6.4`): that group was not done, and nothing is written for it. What every section
    /// at zero does is ``SetEditorSections/writesNothing``'s.
    var sets: Int? {
        guard let count = LocalizedNumberField.count(setsText, locale: locale),
            count >= minimumSets
        else {
            return nil
        }
        return count
    }

    /// This draft with its set count moved by `steps`, floored at ``minimumSets``. See
    /// ``adjustingWeight(by:)``.
    ///
    /// - Parameter steps: How many sets to move — negative is down.
    /// - Returns: The adjusted draft.
    func adjustingSets(by steps: Int) -> SetDraft {
        var adjusted = self
        let moved = max(minimumSets, (sets ?? minimumSets) + steps)
        adjusted.setsText = LocalizedNumberField.render(Double(moved), locale: locale)
        adjusted.details = Self.details(of: adjusted, count: adjusted.details.isEmpty ? 0 : moved)
        return adjusted
    }

    /// One entry per set, filled in from the form's own fields (`FR-17.9.4`).
    ///
    /// **Prefilled rather than blank**, which is what makes the fold an *override*: a lifter who
    /// opens it to change the last set's reps must not have to retype the first two.
    ///
    /// **An entry built here carries no ``SetDetailDraft/storedWeight``**, so every row it writes
    /// takes the group's load. That is the rule for a set *added* in the sheet, and it is also what
    /// ``resettingDetails()`` costs a stored one: once the form's reps or set count have moved, the
    /// entries no longer stand one to one over the sets they were filled from, so a stored warm-up
    /// loses its carried load **and its warm-up mark** — and the switch above the fold says
    /// *working* already, so it does not move to report either.
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
    /// group's load unless that entry was filled in from a set stored at another one
    /// (`FR-18.6.8`).
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

    /// One row — one set's own answers over the group's load, or over the load it carries.
    ///
    /// **The load is the group's unless the entry carries one** (`FR-18.6.8`, `Q-18.11`). A warm-up
    /// stored at its own load keeps it; a warm-up stored at the group's load, which is every one
    /// this sheet has ever written, carries none and so follows an edit of the load field.
    ///
    /// - Parameters:
    ///   - values: What the form says.
    ///   - detail: What this set says instead.
    /// - Returns: The row, or `nil` where the entry does not resolve.
    static func row(_ values: SetEntryValues, applying detail: SetDetailDraft) -> SetEntryValues? {
        guard let reps = detail.reps, detail.rpe != .invalid else { return nil }
        return SetEntryValues(
            weight: detail.storedWeight ?? values.weight,
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
    /// **The form is filled in from the first *working* set, not the first set** (`FR-18.6.8`).
    /// Warm-ups are placed by position rather than by load, so a group can be led by one at a
    /// lighter load — and the load, reps, rating and kind above the fold describe the work. A group
    /// of warm-ups alone falls back to its first set, which is the only set it has to describe. The
    /// count is still every set of the group, warm-ups included: the rewrite is positional.
    ///
    /// - Parameters:
    ///   - row: The checklist row.
    ///   - unit: The unit to render the load in.
    ///   - locale: The locale to render the numbers in.
    init(answering row: SetEditorRow, unit: MassUnit, locale: Locale) {
        self.init(unit: unit, locale: locale)
        if let form = Self.formSet(of: row.logged) {
            weightText = LocalizedNumberField.render(form.weight, in: unit, locale: locale)
            repsText = LocalizedNumberField.render(Double(form.reps), locale: locale)
            setsText = LocalizedNumberField.render(Double(row.logged.count), locale: locale)
            if let rpe = form.rpe {
                rpeText = LocalizedNumberField.render(rpe, locale: locale)
            }
            isWarmup = form.isWarmup
            modifiers = form.modifiers
            notes = form.notes
            if !Self.isUniform(row.logged) {
                details = Self.details(of: row.logged, at: form.weight, locale: locale)
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

    /// The stored set the form above the fold is filled in from (`FR-18.6.8`).
    ///
    /// **The first working set, and the first set only where the group has no working one.** Which
    /// sets can be in one group at all is ``SetEditorSections/loggedGroups(_:)``'s: its working
    /// sets share a load, so any of them would answer the same, and a warm-up would answer with a
    /// load the group did not work at.
    ///
    /// - Parameter logged: The stored sets, in order.
    /// - Returns: The set, or `nil` where nothing is logged.
    static func formSet(of logged: [SetEntry]) -> SetEntry? {
        logged.first { !$0.isWarmup } ?? logged.first
    }

    /// Whether the form above the fold can say every stored set.
    ///
    /// **The load is compared** (`FR-18.6.8`): a set stored at a load the form does not say keeps
    /// that load through the rewrite, ``details(of:at:locale:)`` is the only thing that carries it,
    /// and so the fold has to be open for that set to exist at all. Within a section only a warm-up
    /// can hold such a load — a working set at another one is another section — and a warm-up
    /// beside working sets already disagrees on `isWarmup`; what the load adds is the group of
    /// **warm-ups alone**, a ramp at three loads and one rep count, which no other field here tells
    /// apart.
    ///
    /// - Parameter logged: The stored sets, in order.
    /// - Returns: Whether the form above the fold can say all of them.
    static func isUniform(_ logged: [SetEntry]) -> Bool {
        guard let form = formSet(of: logged) else { return true }
        return logged.allSatisfy {
            $0.weight == form.weight && $0.reps == form.reps && $0.rpe == form.rpe
                && $0.isWarmup == form.isWarmup && $0.notes == form.notes
                && $0.modifiers == form.modifiers
        }
    }

    /// One entry per stored set, filled in from it (`FR-17.7.5`, `FR-18.6.8`).
    ///
    /// **A set stored at `load` carries no ``SetDetailDraft/storedWeight``, and one stored at any
    /// other load carries its own.** The first is what makes an edit of the load field reach every
    /// set the sheet itself wrote (`Q-18.11`); the second is what stops a save the lifter did not
    /// mean to make rewriting a warm-up's load to the group's.
    ///
    /// - Parameters:
    ///   - logged: The stored sets, in order.
    ///   - load: What the form above the fold says — ``formSet(of:)``'s set's.
    ///   - locale: The locale the numbers are rendered in.
    /// - Returns: The entries.
    static func details(of logged: [SetEntry], at load: Weight, locale: Locale) -> [SetDetailDraft] {
        logged.map { set in
            SetDetailDraft(
                locale: locale,
                repsText: LocalizedNumberField.render(Double(set.reps), locale: locale),
                rpeText: set.rpe.map { LocalizedNumberField.render($0, locale: locale) } ?? "",
                isWarmup: set.isWarmup,
                notes: set.notes,
                modifiers: set.modifiers,
                storedWeight: set.weight == load ? nil : set.weight)
        }
    }
}
