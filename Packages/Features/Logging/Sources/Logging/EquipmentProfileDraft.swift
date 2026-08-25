import Foundation
import PowerliftingCore
import RepositoryInterface

/// One denomination as the editor holds it: the plate, and how many pairs of it the gym has
/// (`FR-1.4.2`).
///
/// **Identified by a value of its own rather than by the plate it names**, because the plate is what
/// the user is editing: two rows are briefly both empty while a second is being added, and a list
/// keyed on the denomination would collapse them into one and take the keystrokes with it.
struct PlateDraft: Identifiable, Equatable {
    /// This row's identity for as long as the form is open. Never stored.
    let id: UUID

    /// The denomination, as typed.
    var weightText: String

    /// How many **pairs** of it, as typed.
    var pairsText: String

    /// A row, empty or filled.
    ///
    /// - Parameters:
    ///   - id: The row's identity. Defaults to a fresh one, which is what an added row wants.
    ///   - weightText: The denomination, as typed.
    ///   - pairsText: The pair count, as typed.
    init(id: UUID = UUID(), weightText: String = "", pairsText: String = "") {
        self.id = id
        self.weightText = weightText
        self.pairsText = pairsText
    }
}

/// Why a profile will not save (`FR-1.13.3`).
///
/// **One reason at a time, in the order the form reads**, rather than a set: the message sits under
/// the save command and names the next thing to fix, and a list of everything wrong with a
/// half-typed form is a wall of text that grows as the user types.
///
/// The four value refusals mirror `PlateInventory`'s exactly — a denomination under a gram, a
/// negative pair count, a repeated denomination, an inventory that overflows — because a draft that
/// resolved past them would be refused again by ``EquipmentRepository/save(_:)``, one screen later
/// and in a diagnostic the user cannot act on.
enum EquipmentDraftRefusal: Equatable {
    /// The bar's field is empty, is not a number in this locale, or is negative.
    case barNotAWeight

    /// The collar's field is, and zero is the answer for a bar loaded without them.
    case collarNotAWeight

    /// A plate row names no usable denomination — empty, unparseable, or under one gram.
    case plateNotAWeight

    /// A plate row's pair count is not a whole number of pairs, or is negative.
    case pairCountNotACount

    /// Two rows name the same denomination. Refused rather than summed, exactly as
    /// `PlateInventory` refuses it: two rows for 20 kg is a duplicated row far more often than it is
    /// a statement about two sets of twenties.
    case repeatedDenomination

    /// The plates multiply out past what can be counted, so no loading could be worked out.
    case inventoryOverflows
}

/// What the equipment editor holds while a profile is being filled in, and what it refuses
/// (`FR-1.4.2`, `FR-1.4.3`).
///
/// **Text, on ``SetDraft``'s argument**, and every crossing back into a number is
/// ``LocalizedNumberField``'s.
///
/// **Nothing is prefilled, and that is `G-6.2` rather than an oversight.** A form that opened on a
/// 20 kg bar and a competition plate set would be a claim about the user's gym that the user did not
/// make — the same claim `EquipmentProfileEntity` refuses to carry as a default argument, and the
/// reason the repository answers `nil` for a lifter who has configured nothing rather than inventing
/// a gym for them.
///
/// **The collar field is one collar.** `PlateCalculator` loads `bar + 2 × collar + 2 × per-side`, so
/// a number entered as the pair doubles every loading the app produces; the field says which it
/// wants, in its own label rather than in a placeholder.
struct EquipmentProfileDraft: Equatable {
    /// The identity a new profile takes when this form is saved.
    ///
    /// **Minted once with the draft rather than at each save**, and that is the difference between
    /// one gym and several. A save is `async` and the command stays on screen while it runs, so a
    /// second tap — an impatient one, or a retry after a write that failed *after* the row landed —
    /// runs ``profile(replacing:)`` again; an identity minted there would be a different one every
    /// time, and each attempt would insert rather than replace. An edit ignores this: the stored
    /// row's own id wins.
    let newProfileID: UUID

    /// The unit ``barText``, ``collarText`` and every plate row are read in — the user's display
    /// preference (`G-3.1`).
    let unit: MassUnit

    /// The locale every field is parsed and rendered against (`G-3.4`).
    let locale: Locale

    /// What the user calls this gym (`FR-1.4.3`). May be left empty: nothing validates a name on the
    /// way in, and a profile with none is still theirs.
    var name: String = ""

    /// The bar's own mass, as typed.
    var barText: String = ""

    /// The mass of **one** collar, as typed. Zero for a bar loaded without them.
    var collarText: String = ""

    /// The denominations stocked, in the order the form lists them.
    var plates: [PlateDraft] = []

    /// An empty draft — `FR-1.4.2`'s create.
    ///
    /// - Parameters:
    ///   - unit: The unit weights are entered in.
    ///   - locale: The locale the numbers are read in.
    ///   - newProfileID: The identity a saved profile takes. Defaults to a fresh one; pass the
    ///     draft's own to re-seed a form the user has already opened.
    init(unit: MassUnit, locale: Locale, newProfileID: UUID = UUID()) {
        self.unit = unit
        self.locale = locale
        self.newProfileID = newProfileID
    }

    /// A draft over a stored profile — `FR-1.4.2`'s edit.
    ///
    /// **The two plate lists are zipped, so a profile whose lists disagree in length opens with the
    /// shorter one's rows.** That is the repair rather than a loss: such a row cannot be projected at
    /// all (`EquipmentProfile.inventory()` refuses it), the editor is the only place it can be fixed,
    /// and saving writes both lists from these rows and so ends the disagreement.
    ///
    /// - Parameters:
    ///   - profile: The stored profile.
    ///   - unit: The unit to render its weights in.
    ///   - locale: The locale to render the numbers in.
    ///   - newProfileID: Unused while editing — the stored row's own id is what a save keeps.
    init(
        editing profile: EquipmentProfile,
        unit: MassUnit,
        locale: Locale,
        newProfileID: UUID = UUID()
    ) {
        self.init(unit: unit, locale: locale, newProfileID: newProfileID)
        name = profile.name
        barText = Self.render(profile.barWeight, unit: unit, locale: locale)
        collarText = Self.render(profile.collarWeight, unit: unit, locale: locale)
        plates = zip(profile.plates, profile.platePairCounts).map { plate, pairs in
            PlateDraft(
                weightText: Self.render(plate, unit: unit, locale: locale),
                pairsText: LocalizedNumberField.render(Double(pairs), locale: locale)
            )
        }
    }

    /// One stored mass, in the field's own unit — see
    /// ``LocalizedNumberField/render(_:in:locale:)``.
    ///
    /// - Parameters:
    ///   - weight: The mass.
    ///   - unit: The unit to write it in.
    ///   - locale: The locale to write it in.
    /// - Returns: The field's contents.
    private static func render(_ weight: Weight, unit: MassUnit, locale: Locale) -> String {
        LocalizedNumberField.render(weight, in: unit, locale: locale)
    }
}

// MARK: - What the draft resolves to

extension EquipmentProfileDraft {
    /// The bar's mass, or `nil` when the field does not hold one.
    var barWeight: Weight? {
        LocalizedNumberField.weight(barText, in: unit, locale: locale)
    }

    /// The mass of one collar, or `nil` when the field does not hold one.
    var collarWeight: Weight? {
        LocalizedNumberField.weight(collarText, in: unit, locale: locale)
    }

    /// The plates, or `nil` when a row does not resolve or the rows contradict each other.
    ///
    /// An empty list is a value rather than an absence: a bar with no plates is a real profile that
    /// loads exactly one weight.
    var inventory: PlateInventory? {
        var entries: [PlateInventory.Entry] = []
        for row in plates {
            guard let plate = LocalizedNumberField.weight(row.weightText, in: unit, locale: locale),
                plate.grams >= 1,
                let pairs = LocalizedNumberField.count(row.pairsText, locale: locale)
            else {
                return nil
            }
            entries.append(PlateInventory.Entry(plate: plate, pairs: pairs))
        }
        return PlateInventory(entries: entries)
    }

    /// Why this draft will not save, or `nil` when it will.
    ///
    /// Evaluated in the form's own order so the message names the field the user would reach next.
    var refusal: EquipmentDraftRefusal? {
        guard barWeight != nil else { return .barNotAWeight }
        guard collarWeight != nil else { return .collarNotAWeight }
        var seen: Set<Int> = []
        for row in plates {
            guard let plate = LocalizedNumberField.weight(row.weightText, in: unit, locale: locale),
                plate.grams >= 1
            else {
                return .plateNotAWeight
            }
            guard LocalizedNumberField.count(row.pairsText, locale: locale) != nil else {
                return .pairCountNotACount
            }
            guard seen.insert(plate.grams).inserted else { return .repeatedDenomination }
        }
        return inventory == nil ? .inventoryOverflows : nil
    }

    /// Whether this draft can be saved.
    var isSavable: Bool { refusal == nil }

    /// Whether nothing has been entered yet.
    ///
    /// **Not the negation of ``isSavable``, and reading it as one hides a refusal.** A form nobody
    /// has filled in and a form filled in wrongly are opposite situations: the first has nothing to
    /// complain about, the second has to say why the save will not go.
    var isBlank: Bool {
        plates.isEmpty
            && [name, barText, collarText].allSatisfy {
                $0.trimmingCharacters(in: .whitespaces).isEmpty
            }
    }

    /// This draft as a record, once ``isSavable`` holds.
    ///
    /// **``EquipmentProfile/isDefault`` is passed through from the stored row rather than decided
    /// here**, and a new profile's is `false`: which gym is the default is a cross-row invariant
    /// that only ``EquipmentRepository/makeDefault(profileID:)`` can hold, and a save does not
    /// honour the flag whatever the record carries.
    ///
    /// **Called twice, this answers with the same identity twice** — see ``newProfileID``, which is
    /// what makes a repeated save replace one row rather than write a second.
    ///
    /// - Parameter existing: The row being edited, or `nil` when this is a new profile.
    /// - Returns: The record to save, or `nil` if the draft does not resolve.
    func profile(replacing existing: EquipmentProfile?) -> EquipmentProfile? {
        guard let barWeight, let collarWeight, let inventory, isSavable else { return nil }
        let now = Date.now
        return EquipmentProfile(
            id: existing?.id ?? newProfileID,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            deletedAt: existing?.deletedAt,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            barWeight: barWeight,
            collarWeight: collarWeight,
            plates: inventory.entries.map(\.plate),
            platePairCounts: inventory.entries.map(\.pairs),
            isDefault: existing?.isDefault ?? false
        )
    }
}
