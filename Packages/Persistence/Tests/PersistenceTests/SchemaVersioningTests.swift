import Foundation
import SwiftData
import Testing

@testable import Persistence

// `TR-0.6.4`: the versioning scaffolding, and the migration mechanism exercised before it matters.
//
// **The migration tests use an on-disk store, and have to.** An in-memory configuration gives every
// container its own empty store, so "open it again at V2" is not expressible — the second container
// would migrate nothing. That is the one place in this suite where `makeContext(for:)` cannot be
// used; ``makeMigratedContext(schema:url:plan:)`` below is its on-disk sibling and takes the same
// ``containerLock``, because concurrent `ModelContainer` construction crashes the process whatever
// the store is.
//
// The probe entities are test-only and deliberately outside `SchemaV1.models`: they exist to be
// migrated, which the nine cannot be while v1 is the only version there is. That is the same split
// `StoredEntityFixtures` and `CloudKitGateTests` already use — the mechanism is proven against
// fixtures so the real models inherit a checked mechanism rather than defining it.

/// A context over `schema` at `url`, migrated through `plan`.
///
/// One container per call and one store per call. The caller owns `url` and deletes it.
func makeMigratedContext(
    schema: Schema,
    url: URL,
    plan: (any SchemaMigrationPlan.Type)?
) throws -> ModelContext {
    containerLock.lock()
    defer { containerLock.unlock() }
    let container = try ModelContainer(
        for: schema,
        migrationPlan: plan,
        configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
    )
    return ModelContext(container)
}

/// A store URL nothing else uses. The caller deletes it with ``removeStore(at:)``.
///
/// Split from ``withTemporaryStore(_:)`` so a test with an `async` body can hold the same URL
/// across two containers without a second copy of the cleanup below.
func makeTemporaryStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "T034-\(UUID().uuidString)")
        .appendingPathExtension("store")
}

/// Deletes a store file and SQLite's `-shm` and `-wal` siblings.
///
/// **`path(percentEncoded: false)`, not `path()`.** `path()` percent-encodes and
/// `URL(fileURLWithPath:)` takes its argument literally, so under a `TMPDIR` containing a space the
/// round trip yields `/tmp/dir%20with%20space/…` and every removal silently misses — silently,
/// because the failure is swallowed. macOS's own temp path has no such character, which is exactly
/// why this would never have been noticed here.
func removeStore(at url: URL) {
    for suffix in ["", "-shm", "-wal"] {
        let path = url.path(percentEncoded: false) + suffix
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
    }
}

/// A store URL nothing else uses, and its cleanup.
func withTemporaryStore(_ body: (URL) throws -> Void) throws {
    let url = makeTemporaryStoreURL()
    defer { removeStore(at: url) }
    try body(url)
}

/// Every model in `models` that does not carry the ``StoredEntity`` conventions.
///
/// Returned rather than asserted so the check is itself testable, and written against the list
/// rather than against nine call sites: `T-0.31` and `T-0.32` each assert the conventions per
/// entity, but a tenth entity added later inherits nothing from an assertion it never joins. This
/// one it cannot avoid — the list it walks is the schema.
func nonConformingModels(in models: [any PersistentModel.Type]) -> [String] {
    models.compactMap { model in
        model is any StoredEntity.Type ? nil : "\(model) does not conform to StoredEntity"
    }
}

@Suite("Schema versioning (TR-0.6.4)")
struct SchemaVersioningTests {
    @Test("Every model in the schema carries the StoredEntity conventions")
    func everyModelConforms() {
        // The count guard first, for `everyModelPasses`'s reason: an empty list has no
        // non-conforming member and would pass by having nothing in it.
        #expect(SchemaV1.models.count == 13)
        #expect(nonConformingModels(in: SchemaV1.models) == [])
    }

    // **This test is a gate, not bookkeeping, and what makes it one was measured.** A second
    // version whose `models` names the same live classes computes the same CoreData checksum as the
    // first, and `NSLightweightMigrationStage`'s initialiser throws `NSInvalidArgumentException`,
    // "Duplicate version checksums detected." — uncatchable, inside `addPersistentStore`, so the app
    // aborts at launch on every store. Found by running the app, after the type-level assertions
    // here had been rewritten to expect two versions and passed. ``AppMigrationPlan`` carries the
    // full account; the point for a reader here is that appending to `schemas` turns this red first.
    //
    // Nothing in this process can assert the crash — it is an ObjC exception raised on CoreData's
    // own queue — so what stands in for it is the count.
    @Test("V1 is version 1.0.0 and the plan names it as the only version")
    func planNamesOneVersion() {
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(AppMigrationPlan.schemas.count == 1)
        #expect(AppMigrationPlan.schemas[0] is SchemaV1.Type)
        // An explicit closure, not `map(\.versionIdentifier)`: a key path into a static member of an
        // existential metatype crashes SILGen on Swift 6.3.3 (signal 5, `Transform::transform`).
        #expect(AppMigrationPlan.schemas.map { $0.versionIdentifier } == [Schema.Version(1, 0, 0)])
        // No stages while there is one version. A stage appearing here without a second schema is
        // the mistake this pins.
        #expect(AppMigrationPlan.stages.isEmpty)
    }

    @Test("A container over the nine, built through the plan, round-trips a row")
    func containerBuildsThroughThePlan() throws {
        // The scaffolding as T-0.42 will use it: the real schema, the real plan, a real store.
        try withTemporaryStore { url in
            let context = try makeMigratedContext(
                schema: Schema(versionedSchema: SchemaV1.self),
                url: url,
                plan: AppMigrationPlan.self
            )
            let exercise = ExerciseEntity(
                name: "Back Squat",
                movement: .squat,
                equipment: .barbell,
                laterality: .bilateral,
                barType: .standard,
                isCustom: false
            )
            context.insert(exercise)
            try context.save()

            let rows = try context.fetch(FetchDescriptor<ExerciseEntity>())
            #expect(rows.count == 1)
            #expect(rows.first?.name == "Back Squat")
        }
    }
}

// MARK: - The no-op migration

// Two versions with identical shapes. `TR-0.6.4`'s "one no-op migration proven to run" in the
// literal sense: nothing about the store changes, so anything that breaks is the mechanism itself.
//
// **What is proven here is that the store survives a version change, not that `AppMigrationPlan`
// performed it.** Those are different claims and only the first is true — see
// `planIsNotWhatPerformsTheMigration` below, which pins the difference rather than leaving this
// suite to imply the stronger one.

enum ProbeSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [ProbeRow.self] }

    @Model
    final class ProbeRow {
        var id: UUID = UUID()
        var label: String = ""

        init(id: UUID = UUID(), label: String) {
            self.id = id
            self.label = label
        }
    }
}

enum ProbeSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [ProbeRow.self] }

    /// Column-for-column identical to ``ProbeSchemaV1/ProbeRow``.
    @Model
    final class ProbeRow {
        var id: UUID = UUID()
        var label: String = ""

        init(id: UUID = UUID(), label: String) {
            self.id = id
            self.label = label
        }
    }
}

/// The shape `AppMigrationPlan` takes at its first real version.
///
/// `.lightweight` is the only stage `G-1.7` permits — `MigrationStage.custom` is what CloudKit
/// mirroring cannot perform, and `scripts/check-cloudkit.sh` fails the lint job on one. Naming it
/// here is safe: that check drops comment lines, which is a thing its self-test proves in both
/// directions.
enum ProbeNoOpPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ProbeSchemaV1.self, ProbeSchemaV2.self] }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: ProbeSchemaV1.self, toVersion: ProbeSchemaV2.self)]
    }
}

@Suite("A no-op migration runs (TR-0.6.4)")
struct NoOpMigrationTests {
    @Test("A store written at V1 opens at V2 with its rows and their identities intact")
    func noOpMigrationPreservesData() throws {
        let alpha = UUID()
        let beta = UUID()

        try withTemporaryStore { url in
            // The V1 container is scoped to this closure so it is released before V2 opens the same
            // file. **Hygiene, not a requirement** — measured: hoisting it into the enclosing scope,
            // so both containers are live at once, passes 10 of 10. Kept because two containers on
            // one SQLite store is a latent flake this suite has no reason to take on, and written
            // down because an unexplained `try { … }()` is the kind of thing a reader deletes.
            try {
                let context = try makeMigratedContext(
                    schema: Schema(versionedSchema: ProbeSchemaV1.self),
                    url: url,
                    plan: nil
                )
                context.insert(ProbeSchemaV1.ProbeRow(id: alpha, label: "alpha"))
                context.insert(ProbeSchemaV1.ProbeRow(id: beta, label: "beta"))
                try context.save()
            }()

            let migrated = try makeMigratedContext(
                schema: Schema(versionedSchema: ProbeSchemaV2.self),
                url: url,
                plan: ProbeNoOpPlan.self
            )
            let rows = try migrated.fetch(FetchDescriptor<ProbeSchemaV2.ProbeRow>())

            // Anchored to the literals written above, not to a re-read of the same store: two empty
            // fetches would otherwise agree with each other.
            #expect(rows.map(\.label).sorted() == ["alpha", "beta"])
            #expect(Set(rows.map(\.id)) == Set([alpha, beta]))
        }
    }
}

// MARK: - What a later version's added column is backfilled with

// The suspicion T-0.30 raised, T-0.31 widened to five column shapes and T-0.33 half-confirmed at the
// metadata layer. This is the other half: what a *lightweight migration* writes into a column added
// at V2, across rows that already exist.
//
// The answer is the expensive one, and `SchemaV1`'s doc comment states the rule it produces. Every
// default below is deliberately not its type's zero value, so "backfilled from the default" and
// "backfilled from nothing" cannot be confused.

enum AddedSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [AddedRow.self] }

    @Model
    final class AddedRow {
        var id: UUID = UUID()
        var label: String = ""

        init(label: String) { self.label = label }
    }
}

enum AddedSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [AddedRow.self] }

    /// ``AddedSchemaV1/AddedRow`` plus one column of every shape the nine entities use.
    @Model
    final class AddedRow {
        var id: UUID = UUID()
        var label: String = ""

        /// A non-optional `UUID` minting its default — the shape that must never be added.
        var addedMintedID: UUID = UUID()

        /// The same column defaulting to a constant instead.
        var addedSentinelID: UUID = SchemaDefaults.unlinkedID

        /// `G-1.8`'s shape, defaulted `true` so a backfill is distinguishable from `false`.
        var addedFlag: Bool = true

        /// The enum-raw-value shape, of which T-0.32 added five.
        var addedRawValue: String = "other"

        /// `EquipmentProfileEntity`'s paired collections.
        var addedInts: [Int] = [7, 8]

        /// `TrainingMaxConfigEntity.percentage` — a ratio the domain type refuses at zero.
        var addedRatio: Double = 0.9

        /// `G-2.5`'s other branch, for contrast.
        var addedOptionalID: UUID?

        /// `ExerciseEntity.ukrainianName`'s own shape — the column `FR-1.14.2` added after v1, and
        /// the reason this suite is read again rather than merely kept green.
        var addedOptionalString: String?

        init(label: String) { self.label = label }
    }
}

enum AddedColumnPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AddedSchemaV1.self, AddedSchemaV2.self] }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: AddedSchemaV1.self, toVersion: AddedSchemaV2.self)]
    }
}

@Suite("A column added at V2 is backfilled from one frozen value")
struct AddedColumnBackfillTests {
    @Test("Every pre-existing row receives the identical minted UUID, and it is the frozen default")
    func mintedColumnCollidesAcrossEveryOldRow() throws {
        try withTemporaryStore { url in
            try {
                let context = try makeMigratedContext(
                    schema: Schema(versionedSchema: AddedSchemaV1.self),
                    url: url,
                    plan: nil
                )
                for label in ["alpha", "beta", "gamma"] {
                    context.insert(AddedSchemaV1.AddedRow(label: label))
                }
                try context.save()
            }()

            let migrated = try makeMigratedContext(
                schema: Schema(versionedSchema: AddedSchemaV2.self),
                url: url,
                plan: AddedColumnPlan.self
            )
            let rows = try migrated.fetch(FetchDescriptor<AddedSchemaV2.AddedRow>())

            #expect(rows.count == 3)
            #expect(Set(rows.map(\.addedMintedID)).count == 1, "the backfill is per row after all")

            // And it is the value SwiftData froze into the metadata, not something the migration
            // chose — which is what makes it differ between two devices upgrading the same data.
            let frozen =
                Schema(versionedSchema: AddedSchemaV2.self)
                .entities.first { $0.name == "AddedRow" }?
                .attributes.first { $0.name == "addedMintedID" }?
                .defaultValue as? UUID
            #expect(frozen != nil)
            #expect(rows.first?.addedMintedID == frozen)

            // A row written after the migration mints its own, so the collision is a property of the
            // backfill and not of the column.
            let fresh = AddedSchemaV2.AddedRow(label: "delta")
            migrated.insert(fresh)
            try migrated.save()
            #expect(fresh.addedMintedID != frozen)
        }
    }

    @Test("Every other shape is backfilled from its declared default, not from the type's zero")
    func otherShapesTakeTheDeclaredDefault() throws {
        try withTemporaryStore { url in
            try {
                let context = try makeMigratedContext(
                    schema: Schema(versionedSchema: AddedSchemaV1.self),
                    url: url,
                    plan: nil
                )
                context.insert(AddedSchemaV1.AddedRow(label: "alpha"))
                try context.save()
            }()

            let migrated = try makeMigratedContext(
                schema: Schema(versionedSchema: AddedSchemaV2.self),
                url: url,
                plan: AddedColumnPlan.self
            )
            let row = try #require(try migrated.fetch(FetchDescriptor<AddedSchemaV2.AddedRow>()).first)

            #expect(row.label == "alpha", "the row is the one V1 wrote")

            // A constant default is the safe form of the column above: every old row gets the
            // sentinel, which is what the sentinel already means.
            #expect(row.addedSentinelID == SchemaDefaults.unlinkedID)

            // `true`, not `false` — so a flag added later asserts something about every set logged
            // before the column existed. `G-1.8`'s v1 flags describe only rows this app wrote; a v2
            // flag would not.
            #expect(row.addedFlag == true)

            #expect(row.addedRawValue == "other")
            #expect(row.addedInts == [7, 8], "a lightweight migration does backfill a collection")

            // Not `0`, which `TrainingMaxConfiguration` would refuse — so the row maps, plausibly
            // and wrongly, rather than refusing to map. The worse of the two failures.
            #expect(row.addedRatio == 0.9)

            // The two shapes that arrive with nothing rather than with something wrong. The second
            // is what `ExerciseEntity.ukrainianName` is: a row seeded before the column existed
            // reads back with no Ukrainian name, not with a blank one and not with another row's.
            #expect(row.addedOptionalID == nil)
            #expect(row.addedOptionalString == nil)
        }
    }

    @Test("The plan is not what performs the migration — `nil` produces the same rows")
    func planIsNotWhatPerformsTheMigration() throws {
        // Found by mutation probe: replacing `plan:` with `nil` left every migration test in this
        // file green. SwiftData infers each lightweight change, so a plan of `.lightweight` stages
        // changes nothing it does — also measured across separate processes and a two-hop
        // V1 -> V2 -> V3 chain, neither of which a test in one process can re-run.
        //
        // **Run against the additive pair rather than the no-op one**, because a no-op migration
        // agreeing with itself is the weakest possible form of this claim. Here there are seven
        // columns to disagree about, including the frozen minted `UUID`, which is process-global and
        // so is expected to be *the same value* in both arms.
        //
        // Pinned rather than merely written down, because the whole value of `AppMigrationPlan`
        // rests on which claim is true. Turning red means SwiftData started consulting the plan,
        // which would make `TR-0.6.4`'s scaffolding load-bearing and wants ``AppMigrationPlan``'s
        // doc comment rewritten.
        var results: [String] = []

        for plan: (any SchemaMigrationPlan.Type)? in [AddedColumnPlan.self, nil] {
            try withTemporaryStore { url in
                try {
                    let context = try makeMigratedContext(
                        schema: Schema(versionedSchema: AddedSchemaV1.self), url: url, plan: nil)
                    context.insert(AddedSchemaV1.AddedRow(label: "alpha"))
                    try context.save()
                }()

                let migrated = try makeMigratedContext(
                    schema: Schema(versionedSchema: AddedSchemaV2.self), url: url, plan: plan)
                let rows = try migrated.fetch(FetchDescriptor<AddedSchemaV2.AddedRow>())
                results.append(
                    rows.map {
                        """
                        \($0.label)|\($0.addedMintedID)|\($0.addedSentinelID)|\($0.addedFlag)\
                        |\($0.addedRawValue)|\($0.addedInts)|\($0.addedRatio)\
                        |\($0.addedOptionalID as Any)|\($0.addedOptionalString as Any)
                        """
                    }.joined(separator: ";"))
            }
        }

        // Anchored to a literal, not only to each other: two empty fetches agree with each other.
        let expected =
            "alpha|\(frozenMintedDefault().map(String.init(describing:)) ?? "?")"
            + "|\(SchemaDefaults.unlinkedID)|true|other|[7, 8]|0.9|nil|nil"
        #expect(results == [expected, expected])
    }
}

/// The value SwiftData froze into ``AddedSchemaV2``'s minted column for this process.
func frozenMintedDefault() -> UUID? {
    Schema(versionedSchema: AddedSchemaV2.self)
        .entities.first { $0.name == "AddedRow" }?
        .attributes.first { $0.name == "addedMintedID" }?
        .defaultValue as? UUID
}

// MARK: - The conformance check can fail

/// A `@Model` that is not a ``StoredEntity``, which is what joining `SchemaV1.models` without the
/// conventions looks like: it compiles, it stores, and nothing but this check objects.
@Model
final class UnconventionalEntity {
    var id: UUID = UUID()

    init() {}
}

@Suite("The schema conformance check can fail")
struct SchemaConformanceGateTests {
    @Test("A model missing the conventions is caught, and named")
    func nonConformingIsCaught() {
        let violations = nonConformingModels(in: [UnconventionalEntity.self])

        #expect(violations == ["UnconventionalEntity does not conform to StoredEntity"])
    }

    @Test("A conforming model reports nothing")
    func conformingIsClean() {
        #expect(nonConformingModels(in: [FixtureEntity.self]) == [])
    }
}
