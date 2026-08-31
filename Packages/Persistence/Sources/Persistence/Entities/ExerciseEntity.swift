import Foundation
import PowerliftingCore
import SwiftData

/// A movement the user can log against — seeded from the catalogue or authored by them
/// (`TR-0.3.1`).
///
/// Its four vocabulary columns draw on `Movement`, `Equipment`, `Laterality` and `BarType`, which
/// live in `PowerliftingCore` and are the only vocabulary there is. What the columns hold and who
/// maps them back is the module-wide raw-`String` rule on ``StoredEntity``.
@Model
final class ExerciseEntity: StoredEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    var name: String = ""

    /// The Ukrainian name (`FR-1.14.2`), or `nil` for an exercise that has only ``name``.
    ///
    /// **The first column added after schema v1**, so it is the first one a lightweight migration
    /// backfills across rows that already exist. Optional and therefore backfilled with *nothing* —
    /// the one shape that arrives absent rather than arriving wrong, which is what a name nobody has
    /// written has to be. See ``SchemaV1``'s three rules; this column is the case they were written
    /// for.
    ///
    /// Named for the language and not for `UK`, which is a region. `RepositoryInterface`'s record
    /// carries the reasoning and the resolution rule.
    var ukrainianName: String?

    /// ``PowerliftingCore/Movement``'s raw value — `TR-0.3.1`'s `movement`.
    var movementRawValue: String = SchemaDefaults.movement

    /// The exercise this one varies, or `nil` for a root exercise.
    var parentExerciseID: UUID?

    /// ``PowerliftingCore/Equipment``'s raw value.
    var equipmentRawValue: String = SchemaDefaults.equipment

    /// ``PowerliftingCore/Laterality``'s raw value.
    var lateralityRawValue: String = SchemaDefaults.laterality

    /// ``PowerliftingCore/BarType``'s raw value — the bar's *category*. Its mass is a property of the
    /// gym and lives on the equipment profile (`TR-0.3.7`).
    var barTypeRawValue: String = SchemaDefaults.barType

    /// How many implements one rep loads at once, at least 1: a barbell, a machine and a goblet
    /// squat are all 1, a dumbbell pair is 2.
    ///
    /// Not in `TR-0.3.1`'s field list. It exists because a logged weight is the load on **one**
    /// implement (`TR-0.2.3`), making `FR-1.5.1`'s tonnage `weight × reps × implements × sides` — and
    /// **neither `Equipment` nor `Laterality` supplies this factor**, since a two-dumbbell bench and
    /// a barbell bench are both bilateral. Nothing enforces the lower bound here; the seed validator
    /// and the DTO layer are where a zero would be caught.
    var implementCount: Int = SchemaDefaults.implementCount

    /// Whether the user authored this exercise (`FR-1.1.3`) rather than the seed catalogue. Required
    /// at `init`: it decides whether a re-import may overwrite the row.
    var isCustom: Bool = false

    /// Hidden from pickers, still present in logged history. Distinct from ``deletedAt``.
    var isArchived: Bool = false

    var notes: String = ""

    /// The estimated one-rep maximum the user entered by hand, in grams (`G-1.1`), or `nil` to use
    /// the computed one (`FR-1.7.5`).
    ///
    /// Not in `TR-0.3.1`'s field list. Optional rather than a sentinel because `Weight` is signed
    /// and zero is a real load, so no in-band value can mean "no override" — and clearing it is
    /// half of what `FR-1.7.5` asks for. Unvalidated here, as every column in this schema is.
    var manualE1RMGrams: Int?

    init(
        id: UUID = UUID(),
        name: String,
        ukrainianName: String? = nil,
        movement: Movement,
        equipment: Equipment,
        laterality: Laterality,
        barType: BarType,
        isCustom: Bool,
        implementCount: Int = SchemaDefaults.implementCount,
        parentExerciseID: UUID? = nil,
        isArchived: Bool = false,
        notes: String = "",
        manualE1RMGrams: Int? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.ukrainianName = ukrainianName
        self.movementRawValue = movement.rawValue
        self.equipmentRawValue = equipment.rawValue
        self.lateralityRawValue = laterality.rawValue
        self.barTypeRawValue = barType.rawValue
        self.isCustom = isCustom
        self.implementCount = implementCount
        self.parentExerciseID = parentExerciseID
        self.isArchived = isArchived
        self.notes = notes
        self.manualE1RMGrams = manualE1RMGrams
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
