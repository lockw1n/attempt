import Foundation
import PowerliftingCore

/// Every schema default this module *chose* — the ones where more than one value was defensible.
///
/// `G-2.5` requires each property to be optional or defaulted and `TR-0.3.1`–`TR-0.3.4` mark only
/// some fields optional, so the rest are defaulted and somebody has to pick. **They are gathered here
/// because a default written inline cannot be tested**: nothing but the store reaches it and `init`
/// overwrites it, so it is unfalsifiable where it is declared. Defaults that carry no choice — `""`,
/// `0`, `nil` — stay on their property.
///
/// **In schema v1 nothing reaches any of them.** Each entity's `init` requires every field whose
/// omission would be a claim, so our own writes never fall back; the columns exist from v1, so no
/// lightweight migration backfills one; and a CloudKit record missing a v1 field could only have been
/// written by a schema version that never existed. A row holding one of these came from something
/// that is not this app. **That stops being true at the first schema version to change this column
/// set** — a column added later is backfilled from its default across every existing row.
///
/// So none of these is a claim about a set or an exercise. Each is a choice of which way to be wrong
/// in a store we did not write, made toward the reading that loses least.
enum SchemaDefaults {
    /// A join key that was never written.
    ///
    /// Stable and shared, so every such row carries one recognisable value and a single predicate
    /// finds them. `UUID()` here would instead mint a *distinct* dangling reference per row, and two
    /// devices defaulting the same row would disagree — a conflict `G-2.4` resolves between two
    /// values that are both meaningless.
    static let unlinkedID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// ``PowerliftingCore/Movement/other`` — the case that claims nothing.
    static let movement = Movement.other.rawValue

    /// ``PowerliftingCore/Equipment/other``, for the same reason as ``movement``.
    static let equipment = Equipment.other.rawValue

    /// ``PowerliftingCore/Laterality/bilateral``.
    ///
    /// The one default here that is safe rather than true: `Laterality` has no unknown case, so some
    /// real answer has to be picked. Reading unilateral work as bilateral undercounts tonnage;
    /// reading bilateral work as unilateral invents volume that was never lifted.
    static let laterality = Laterality.bilateral.rawValue

    /// ``PowerliftingCore/BarType/other`` — not `.noBar` and not `.standard`, both of which assert
    /// something about the equipment.
    static let barType = BarType.other.rawValue

    /// One implement. Two-implement work is the exception and states it per exercise.
    static let implementCount = 1

    /// The present, for a session whose training date was never written.
    ///
    /// Not a distant-past sentinel, which would sort ahead of every real session and so win every
    /// personal-record tie-break (`TR-0.2.8`). Computed rather than stored, so each row gets its own.
    static var sessionDate: Date { .now }

    /// A set nobody classified is not a warmup…
    ///
    /// …and not completed either, so every analytics filter passes over it. A row this app did not
    /// write must not be able to mint a personal record — `FR-1.6.3` badges one at the moment it is
    /// logged, and a wrong record outlives the row that caused it, where a set missing from a
    /// dashboard is recoverable the moment anybody notices (`G-1.8`).
    static let isWarmup = false

    /// See ``isWarmup``.
    static let isCompleted = false
}
