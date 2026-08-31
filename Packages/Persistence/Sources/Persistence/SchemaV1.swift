import Foundation
import SwiftData

/// The store's model list — every `@Model` in this module, and the only list of them (`TR-0.6.4`).
///
/// **One list, not two.** `scripts/check-cloudkit.sh` parses the markers around the array and
/// compares it against every `@Model` under `Sources/`, so an entity cannot join the store without
/// joining the CloudKit audit (`DOD-0.4`). Both things read this array; neither keeps a copy.
///
/// **A column added in a later version is backfilled from one frozen value, written once.** A
/// lightweight stage stamps every pre-existing row with the default SwiftData froze into the model's
/// metadata on the launch that performed the migration, and persists it — a later launch, whose
/// frozen default is a different value, still reads back the one the migration wrote. In schema v1
/// nothing reaches a default at all (see ``SchemaDefaults``); the first version to add a column is
/// where that stops being true, and three things follow:
///
/// - **Never `= UUID()` on a column added after v1.** Every pre-existing row would collide on one
///   identity, and `G-2.5` forbids the unique constraint that would notice. A join key added later
///   defaults to ``SchemaDefaults/unlinkedID``; anything that must be distinct per row is `UUID?`,
///   which arrives `nil` rather than arriving wrong.
/// - **A defaulted `Bool` added later is a claim about history**, not a placeholder — every set
///   logged before the column existed asserts it, where `G-1.8`'s v1 flags only ever describe rows
///   this app wrote.
/// - **Two devices migrate independently**, so a minted default disagrees across them on rows that
///   were identical before the upgrade, and `G-2.4` resolves between two meaningless values.
///
/// **``ExerciseEntity/ukrainianName`` is the first column those three rules apply to**, and it takes
/// the branch the first of them names: optional, so every row written before it existed reads back
/// with nothing rather than with something wrong.
///
/// **This enum does not freeze v1's columns, and cannot** — its ``models`` names the module's live
/// classes, so it describes whatever shape those classes currently have rather than the shape v1
/// stores were written with. A column added here is therefore added *to v1's declaration*, and the
/// identifier stays `1.0.0`. That is not a shortcut; ``AppMigrationPlan`` has the measurement that
/// makes it the only available answer, and the crash the other one produces.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    // audited-models:begin
    static var models: [any PersistentModel.Type] {
        [
            ExerciseEntity.self,
            WorkoutSessionEntity.self,
            ExerciseEntryEntity.self,
            SetEntryEntity.self,
            BodyweightEntryEntity.self,
            TrainingMaxConfigEntity.self,
            EquipmentProfileEntity.self,
            UserSettingsEntity.self,
            PersonalRecordCacheEntity.self,
        ]
    }
    // audited-models:end
}

/// The migration plan every `ModelContainer` in this app is built with (`TR-0.6.4`).
///
/// **It has no stages, and while `G-1.7` holds it never changes what a migration does.** Measured:
/// a store written at an older version reads back identically whether it is opened through a plan
/// or with `migrationPlan: nil` — one hop or two, same process or a later launch. SwiftData infers
/// every lightweight change, and `MigrationStage.lightweight` carries no `willMigrate` or
/// `didMigrate`; the stage that does is `.custom`, which is the shape CloudKit mirroring cannot
/// perform and which `scripts/check-cloudkit.sh` fails the lint job on.
///
/// So this is a declaration, not a mechanism, and it is worth declaring for two reasons. It is the
/// one place a version history would be written down. And it is where `G-1.7` becomes visible: a
/// stage that needed to be `.custom` would have to be written here, where the gate is looking.
///
/// **A migration whose correctness depends on this plan being consulted is a migration `G-1.7` has
/// already refused.**
///
/// **A SECOND VERSION CANNOT BE ADDED WITHOUT FREEZING A COPY OF EVERY ENTITY, and adding one
/// without that crashes the app at launch.** Measured against a real simulator store while
/// `FR-1.14.2` was adding a column: a `SchemaV2` whose `models` names ``SchemaV1``'s live classes
/// makes both versions compute the same CoreData checksum, and `NSLightweightMigrationStage`'s
/// initialiser refuses that pair by throwing `NSInvalidArgumentException`, *"Duplicate version
/// checksums detected."* It is raised inside `addPersistentStore` and nothing in Swift catches it —
/// `SIGABRT` at `ModelContainer` construction, on a fresh store as readily as on an old one.
///
/// So the version identifier is not free to move, and a column added to this schema is added to
/// ``SchemaV1``'s own declaration at `1.0.0`. SwiftData infers the additive change either way, which
/// is what makes that survivable: the store migrates, and what is lost is only the written record
/// that its shape changed. **A real second version means a per-version copy of all nine entity
/// classes** — the shape `SchemaVersioningTests`' probe enums use — which is a task, not an edit.
/// `planNamesOneVersion` is what holds this shut: appending to ``schemas`` turns it red before
/// anyone runs the app.
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }

    static var stages: [MigrationStage] { [] }
}
