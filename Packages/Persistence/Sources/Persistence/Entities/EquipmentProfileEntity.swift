import Foundation
import PowerliftingCore
import SwiftData

/// One gym's bar, collars and plates (`TR-0.3.7`, `FR-1.4.2`, `FR-1.4.3`).
///
/// **``collarWeightGrams`` is the mass of ONE collar**, matching `PlateCalculator`, which loads
/// `bar + 2 × collar + 2 × (per-side plates)`. Storing the pair here loads every bar wrong by twice
/// the collars, and neither the column name nor `FR-1.4.2` distinguishes the two readings.
///
/// **No bar type, ever.** A bar's *category* belongs to the exercise (`BarType` on `ExerciseEntity`)
/// and is the same in every gym; a bar's *mass* is this profile's and differs between them. A 20 kg
/// men's bar and a 15 kg women's bar are both `.standard`, so nothing may derive one from the other.
///
/// **A profile holds only what a call site stated.** `init` gives bar, collars and inventory no
/// default arguments, so nothing can acquire a denomination by omission — the same enforcement shape
/// `G-1.8` gets on a set's two flags. It matters because a shipped "competition" preset would be a
/// published data claim and `G-6.2` wants those cited: adding one means citing the IPF Technical
/// Rules Book or labelling it unverified in the words `RPETable.standard` uses, never transcribing a
/// plate set from memory under an implied citation.
@Model
final class EquipmentProfileEntity: StoredEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// The user's name for this profile — "home gym", "the meet" (`FR-1.4.3`).
    var name: String = ""

    /// The bar's own mass, in grams (`G-1.1`).
    var barWeightGrams: Int = 0

    /// The mass of **one** collar, in grams (`G-1.1`). Zero for a bar loaded without them.
    var collarWeightGrams: Int = 0

    /// The denominations stocked, in grams, heaviest first.
    ///
    /// Positionally paired with ``platePairCounts``: index *i* of each describes one denomination.
    /// Both are `private(set)` and can only be written **together**, by one of the two
    /// `replaceInventory` methods, so neither can be left updated while the other is not.
    ///
    /// **That is all `private(set)` buys, and it is not "the columns are always well formed".** The
    /// raw writer exists because a profile that breaks `PlateInventory`'s invariants has to be
    /// storable — a restore that could not put one back would lose the profile and its name, which
    /// is the outcome the whole record shape exists to avoid (`FR-1.11.3`). What such a row costs
    /// is decided one layer up, by `EquipmentProfile.inventory()`.
    private(set) var plateGrams: [Int] = []

    /// How many **pairs** of each denomination in ``plateGrams`` the gym has. Zero is legal.
    private(set) var platePairCounts: [Int] = []

    /// Whether this is the profile the plate calculator reaches for by default.
    ///
    /// Nothing stops two rows claiming it — `G-2.5` forbids unique constraints and a store cannot
    /// enforce a cross-row predicate anyway — so "exactly one default" is a repository invariant
    /// (`TR-0.4.3`), the same shape as `id` uniqueness.
    var isDefault: Bool = false

    init(
        id: UUID = UUID(),
        name: String,
        barWeightGrams: Int,
        collarWeightGrams: Int,
        plateGrams: [Int],
        platePairCounts: [Int],
        isDefault: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.barWeightGrams = barWeightGrams
        self.collarWeightGrams = collarWeightGrams
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        replaceInventory(plateGrams: plateGrams, platePairCounts: platePairCounts)
    }

    /// Creates a profile from a validated inventory — the initialiser an authoring call site wants.
    ///
    /// The raw-array one above exists for the restore and sync paths; see
    /// ``replaceInventory(plateGrams:platePairCounts:)`` for why both are needed.
    convenience init(
        id: UUID = UUID(),
        name: String,
        barWeightGrams: Int,
        collarWeightGrams: Int,
        inventory: PlateInventory,
        isDefault: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.init(
            id: id,
            name: name,
            barWeightGrams: barWeightGrams,
            collarWeightGrams: collarWeightGrams,
            plateGrams: inventory.entries.map(\.plate.grams),
            platePairCounts: inventory.entries.map(\.pairs),
            isDefault: isDefault,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Replaces the stocked denominations from a validated inventory.
    ///
    /// The writer every call site that is *authoring* a profile should use: `PlateInventory`
    /// normalises to heaviest-first and refuses a repeated denomination rather than summing it, so
    /// a profile the app itself produces cannot break either invariant.
    func replaceInventory(with inventory: PlateInventory) {
        replaceInventory(
            plateGrams: inventory.entries.map(\.plate.grams),
            platePairCounts: inventory.entries.map(\.pairs))
    }

    /// Replaces the stocked denominations verbatim, pairing and all, without asking whether they
    /// describe a gym.
    ///
    /// **For restoring or syncing a row, never for authoring one.** It is the only way to write a
    /// profile whose lists repeat a denomination or disagree in length — which is exactly what a
    /// backup of such a row has to be able to reinstate (`FR-1.11.3`), and what
    /// `replaceInventory(with:)` cannot express because the domain type refuses to represent it.
    /// The refusal is not lost, it moves: `EquipmentProfile.inventory()` raises it the moment
    /// anything asks what the profile means.
    ///
    /// No normalisation either — a heaviest-first order is `PlateInventory`'s guarantee, not this
    /// column's, and re-sorting here would silently repair half of a row a repair tool needs to see
    /// whole.
    func replaceInventory(plateGrams: [Int], platePairCounts: [Int]) {
        self.plateGrams = plateGrams
        self.platePairCounts = platePairCounts
    }
}
