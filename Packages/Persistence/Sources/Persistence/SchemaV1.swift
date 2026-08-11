import Foundation
import SwiftData

/// The store's shape at version 1 — every `@Model` in this module, and the only list of them
/// (`TR-0.6.4`).
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
/// one place a version history is written down, which is what makes adding `SchemaV2` an edit
/// rather than a decision. And it is where `G-1.7` becomes visible: a stage that needed to be
/// `.custom` would have to be written here, where the gate is looking.
///
/// **A migration whose correctness depends on this plan being consulted is a migration `G-1.7` has
/// already refused.** Adding a version means appending to ``schemas`` and one `.lightweight` stage
/// to ``stages``.
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }

    static var stages: [MigrationStage] { [] }
}
