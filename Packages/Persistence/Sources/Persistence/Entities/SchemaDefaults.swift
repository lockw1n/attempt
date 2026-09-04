import Foundation
import PowerliftingCore
import RepositoryInterface

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
///
/// **Every default here is evaluated once per process, not once per row.** SwiftData freezes the
/// value into the model's metadata when it is first built, so a `Date` default is the moment the app
/// launched and a `UUID()` default is one value shared by every row that reaches it — the same value
/// on this launch, a different one on the next, and a different one again on another device. Writing
/// a default as a computed `var` does not change that; nothing but the store reads these.
enum SchemaDefaults {
    /// A reference that was never written — a join key, or the anonymous user id (`TR-1.10`).
    ///
    /// Stable *across* launches and devices, so every such row carries one recognisable value and a
    /// single predicate finds them all. `UUID()` here would be frozen per launch instead: one
    /// dangling reference this run, another the next, and two devices defaulting the same row would
    /// disagree — a conflict `G-2.4` resolves between two values that are both meaningless.
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
    /// personal-record tie-break (`TR-0.2.8`). "The present" means the launch, not the row — see the
    /// type's note.
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

    /// The present, for a bodyweight reading whose date was never written.
    ///
    /// The same direction as ``sessionDate``, with the same once-per-launch caveat, and for a related
    /// reason: a distant-past sentinel would anchor the left edge of every bodyweight chart and
    /// rolling average (`FR-3.5.1`) to a day nobody weighed themselves, and would never fall inside
    /// `FR-1.8.2`'s de-duplication window, so it would be a permanent phantom. Landing on today is
    /// wrong in a way somebody notices at once.
    static var bodyweightDate: Date { .now }

    /// ``RepositoryInterface/BodyweightSource/manual``, for a reading whose provenance was never written.
    ///
    /// Not `.healthKit`, which would make the row a de-duplication candidate (`FR-1.8.2`) and let it
    /// suppress a reading the user actually typed. A spurious manual entry is a row they can delete.
    static let bodyweightSource = BodyweightSource.manual.rawValue

    /// The distant past, for a training-max configuration whose effective date was never written.
    ///
    /// **The opposite direction from ``sessionDate`` and ``bodyweightDate``, because the lookup runs
    /// the other way.** A configuration is read as "the latest one effective on or before today", so
    /// the newest wins — and a row defaulting to *now* would displace the user's real configuration
    /// from this moment on. Defaulting to the distant past loses every such contest and only ever
    /// applies where the user has configured nothing.
    static let effectiveFrom = Date.distantPast

    /// ``RepositoryInterface/TrainingMaxSourceKind/manual``, for a configuration whose source was never written.
    ///
    /// The one case that cannot quietly produce a plausible number: `manualWeightGrams` is `nil` on
    /// such a row, so the configuration refuses to resolve and says so, where `.percentOfE1RM` would
    /// silently hand back 90% of the user's e1RM as though they had asked for it. It is also
    /// `FR-1.5.1.5`'s override — the state in which the derived pipeline is *not* running — which is
    /// the right thing to say about a row this app did not write.
    static let trainingMaxSource = TrainingMaxSourceKind.manual.rawValue

    /// `FR-1.5.1.2`'s 90%, as the ratio the domain type uses.
    static let trainingMaxPercentage = TrainingMaxConfiguration.defaultPercentage

    /// A 2.5 kg loading step — one pair of 1.25 kg plates, the smallest change a standard set makes.
    ///
    /// Chosen rather than left at zero because zero is **not available**: `RoundingRule` refuses an
    /// increment below one gram, so a row defaulting to zero could not be mapped to a rule at all.
    static let roundingIncrementGrams = 2500

    /// ``PowerliftingCore/RoundingStrategy/nearest`` — the direction that moves a target least.
    static let roundingStrategy = RoundingStrategy.nearest.rawValue

    /// ``PowerliftingCore/MassUnit/kilograms``.
    ///
    /// Kilogram display is lossless (1 kg is exactly 1000 g) where pound display is lossy by up to
    /// half a gram, so this is the unit that cannot misreport a stored weight.
    static let displayUnit = MassUnit.kilograms.rawValue

    /// ``PowerliftingCore/E1RMFormulaID/defaultFormula``, which is the one place that value is
    /// decided — the formula a lifter gets before opening settings *and* the fallback for a name
    /// this app cannot read. Never a second constant: two would drift, invisibly.
    static let e1RMFormula = E1RMFormulaID.defaultFormula.rawValue

    /// ``RepositoryInterface/ThemePreference/system`` — a *column* default, and deliberately not the one
    /// ``RepositoryInterface/SettingsRepository/settings()`` gives a first-launch row.
    ///
    /// The two answer different questions. This one backfills a row that already exists and never
    /// carried a theme, where the only honest answer is "no preference recorded"; that one mints
    /// the row a lifter meets, where `G-7.1`'s dark is what the app has already adopted and
    /// picking *System* later is a preference in its own right.
    static let theme = ThemePreference.system.rawValue

    /// `FR-1.7.1`'s ninety days, read from the one place that number is written.
    static let e1RMLookbackDays = UserSettings.defaultE1RMLookbackDays

    /// `NFR-1.9` read as written — see ``RepositoryInterface/UserSettings/defaultKeepScreenAwake``.
    static let keepScreenAwake = UserSettings.defaultKeepScreenAwake

    /// ``RepositoryInterface/RecentRecordsScope/dashboardLifts``, read from the one place
    /// `FR-16.3.1`'s default is written.
    ///
    /// **The first default here that a real migration will reach**, which is what the type's note
    /// says stops being hypothetical at the first schema version to change this column set. It is
    /// safe to reach: a backfilled row asserts the same scope a fresh install gets.
    static let recentRecordsScope = UserSettings.defaultRecentRecordsScope.rawValue

    /// `FR-16.3.4` read as written — see
    /// ``RepositoryInterface/UserSettings/defaultRecentRecordsShowsBaselines``.
    static let recentRecordsShowsBaselines = UserSettings.defaultRecentRecordsShowsBaselines

    /// The distant past, for a cached personal record whose date was never written.
    ///
    /// The direction that cannot mint a badge: `FR-1.6.3` announces a record at the moment it is
    /// logged, and a wrong announcement outlives the row that caused it, so a row this app did not
    /// write must not be able to read as "achieved just now". Nothing is lost by it looking old.
    ///
    /// The same value as ``effectiveFrom`` and a different argument — that one is about losing a
    /// lookup, this one about losing a badge. Kept apart so neither can be changed on the other's
    /// reasoning.
    static let achievedAt = Date.distantPast
}
