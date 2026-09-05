import Foundation
import SwiftData
import Testing

@testable import Persistence

// `DOD-0.4`'s audit, as the half of it a machine can run. `G-2.5`'s three constraints are read off
// SwiftData's own schema metadata rather than asserted about the source, so a column added later is
// audited whether or not anyone remembers this file. The judgements a walk of the metadata cannot
// make — what a defaulted `id` *means*, which columns are join keys — are in
// `docs/phase-0/cloudkit-checklist.md` beside the per-model table.
//
// **Why this does not construct a CloudKit-backed container.** It cannot: with
// `cloudKitDatabase: .private(…)` CoreData's mirroring delegate reaches CloudKit on
// `com.apple.coredata.cloudkit.queue` and traps in `containerWithIdentifier:options:`, killing the
// test process from a queue no `do`/`catch` can reach — measured, 3 of 3 full-suite runs, within
// 50 ms of construction, valid schema or not. With `.automatic` and no entitlement the whole
// mechanism is inert, and a schema CloudKit rejects loads clean — also measured, so a `.automatic`
// container is a test that passes for any schema at all. The full measurement is in T-0.33's file.
//
// What that costs is fidelity, and the gap is narrower than it looks — CoreData's own validator was
// run over this exact schema, it just cannot be run *here*. Both directions were measured on a real
// on-disk store with `.private(…)`, one process per case:
//
//   the nine       loaded clean, 3 of 3, with no store-load error — so the collection columns
//                  (`modifiers`, `plateGrams`, `platePairCounts`) are CloudKit-legal by CoreData's
//                  own reckoning and not merely by this walk's
//   undefaulted    "CloudKit integration requires that all attributes be optional, or have a
//                   default value set. The following attributes are marked non-optional but do not
//                   have a default value:"
//   unique         "CloudKit integration does not support unique constraints. The following
//                   entities are constrained:"
//   relationship   "CloudKit integration requires that all relationships have an inverse, the
//                   following do not:"
//
// Same configuration for all four, so the validator demonstrably ran on the passing case too. Each
// broken fixture below reproduces the constraint behind one refusal; what is *not* re-run per commit
// is CoreData itself.

// The models this audit covers are `SchemaV1.models` — the schema itself, not a second list beside
// it. Two lists that must agree is the drift `scripts/check-cloudkit.sh` check 4 exists to prevent,
// so it now parses the markers around `SchemaV1.models`; an entity that never joins the store
// cannot evade the audit by not being in it either.

/// Every way `schema` breaks `G-2.5`, empty when it honours it.
///
/// Returned rather than asserted so the check is itself testable — `CloudKitGateTests` holds three
/// models that break it on purpose. Each violation names the column, because "the schema fails" is
/// not a finding anyone can act on.
func cloudKitViolations(in schema: Schema) -> [String] {
    var violations: [String] = []

    for entity in schema.entities.sorted(by: { $0.name < $1.name }) {
        for attribute in entity.attributes.sorted(by: { $0.name < $1.name }) {
            if !attribute.isOptional && attribute.defaultValue == nil {
                violations.append("\(entity.name).\(attribute.name) is non-optional with no default")
            }
            if attribute.isUnique {
                violations.append("\(entity.name).\(attribute.name) is unique")
            }
        }

        if !entity.uniquenessConstraints.isEmpty {
            violations.append("\(entity.name) declares a uniqueness constraint")
        }

        // Stronger than `G-2.5`'s "all relationships optional", and deliberately: this schema joins
        // by raw `UUID` and declares none at all, which satisfies the clause vacuously and also
        // makes a `.cascade` delete rule that would defeat soft delete unrepresentable. Optionality
        // is not checked because it is not what CoreData objects to — the measured refusal for a
        // relationship is about a missing inverse, and a to-many array reports `isOptional == false`
        // while being perfectly legal. A schema that acquires a relationship needs a real re-audit,
        // not this line.
        for relationship in entity.relationships.sorted(by: { $0.name < $1.name }) {
            violations.append("\(entity.name).\(relationship.name) is a relationship")
        }
    }

    return violations
}

/// Every `UUID` column other than `id`, split by whether its default is the shared sentinel or a
/// value the schema minted.
///
/// Split out for the same reason `cloudKitViolations` is: the interesting half is `minted`, which is
/// empty today and would stay empty in a test that only ever saw this schema.
func mintedUUIDColumns(in schema: Schema) -> (sentinels: [String], minted: [String]) {
    var sentinels: [String] = []
    var minted: [String] = []

    for entity in schema.entities.sorted(by: { $0.name < $1.name }) {
        for attribute in entity.attributes.sorted(by: { $0.name < $1.name }) where attribute.name != "id" {
            guard let value = attribute.defaultValue as? UUID else { continue }
            let column = "\(entity.name).\(attribute.name)"
            if value == SchemaDefaults.unlinkedID { sentinels.append(column) } else { minted.append(column) }
        }
    }

    return (sentinels, minted)
}

@Suite("CloudKit compatibility (G-2.5)")
struct CloudKitCompatibilityTests {
    // The versioned form, not `Schema(SchemaV1.models)`: it is what a container actually loads, and
    // it carries the version identifier a migration keys off.
    private let schema = Schema(versionedSchema: SchemaV1.self)

    @Test("All seventeen entities are in the audited schema")
    func seventeenEntities() {
        // Without this the audit passes vacuously on an empty or mis-built schema, which is exactly
        // how a checklist becomes a markdown table.
        #expect(schema.entities.count == 17)
        #expect(SchemaV1.models.count == 17)
    }

    @Test("Every property is optional or defaulted, nothing is unique, nothing is a relationship")
    func everyModelPasses() {
        #expect(cloudKitViolations(in: schema) == [])
    }

    @Test("The relationship clause is satisfied by there being none, not by their optionality")
    func noRelationships() {
        let relationships = schema.entities.flatMap { entity in
            entity.relationships.map { "\(entity.name).\($0.name)" }
        }

        #expect(relationships == [])
    }

    @Test("A defaulted column's default is one value per process, not one per row")
    func defaultsAreEvaluatedOnce() {
        // The sharpest thing in the audit, and it is not what the source reads like. `id: UUID =
        // UUID()` mints per instance down the `init` path, but the *store's* default is evaluated
        // once when the model's metadata is built and frozen there — so every row that reaches the
        // default gets the same id, not a fresh one, and `G-2.5` forbids the unique constraint that
        // would notice. `createdAt` is the same shape: a defaulted row is stamped with the moment
        // the process launched.
        //
        // Turning red here would mean SwiftData started minting per row, which is better news than
        // the current behaviour and would want the checklist's `id` line rewritten.
        let rebuilt = Schema(versionedSchema: SchemaV1.self)

        for name in ["id", "createdAt", "updatedAt"] {
            let first = defaultValue(of: name, on: "ExerciseEntity", in: schema)
            let second = defaultValue(of: name, on: "ExerciseEntity", in: rebuilt)
            // Both sides anchored to non-nil, or two absent columns would agree with each other.
            #expect(first != nil, "\(name) has no stored default")
            #expect(String(describing: first) == String(describing: second), "\(name) is re-evaluated")
        }

        #expect(defaultValue(of: "id", on: "ExerciseEntity", in: schema) is UUID)
        #expect(defaultValue(of: "id", on: "ExerciseEntity", in: schema) as? UUID != SchemaDefaults.unlinkedID)
    }

    @Test("The fifteen defaulted UUID columns that are not identities default to the all-zero sentinel")
    func sentinelColumns() {
        // Fourteen join keys and one anonymous user id — three distinct failure modes on one type,
        // which is why the checklist gives them a line rather than a tick. Pinned here so a later
        // column cannot quietly take `UUID()` instead and manufacture a reference, or an account.
        let expected = [
            "ExerciseEntryEntity.exerciseID",
            "ExerciseEntryEntity.sessionID",
            "PersonalRecordCacheEntity.exerciseID",
            "PersonalRecordCacheEntity.sourceSetID",
            "PlannedTargetGroupEntity.exerciseEntryID",
            "ProgramDayEntity.programID",
            "ProgramDayEntity.routineID",
            "ProgramRunEntity.programID",
            "RoutineExerciseEntity.exerciseID",
            "RoutineExerciseEntity.routineID",
            "RoutineTargetGroupEntity.routineExerciseID",
            "SetEntryEntity.entryID",
            "TrainingMaxConfigEntity.exerciseID",
            "TrainingMaxHistoryEntity.exerciseID",
            "UserSettingsEntity.userID",
        ]

        let columns = mintedUUIDColumns(in: schema)

        #expect(columns.sentinels == expected)
        #expect(columns.minted == [], "a non-identity UUID column defaults to a minted value")
    }

    @Test("A cached row arrives at the reserved version, not at the first real one")
    func cacheDefaultsToNoVersion() {
        let value = defaultValue(of: "computationVersion", on: "PersonalRecordCacheEntity", in: schema)

        #expect(value as? Int == 0)
    }

    @Test("Both halves of the plate inventory default to empty, so a half-delivered record is empty")
    func pairedCollectionsDefaultTogether() {
        // CloudKit stores the two `[Int]` columns as separate record fields and nothing over there
        // enforces the pairing this side holds with `private(set)` and one writer. Both defaulting
        // to empty is what makes a record carrying one list and not the other read as a length
        // disagreement — visible, and refused by the mapping — rather than as an inventory that
        // silently lost its counts. Reconciling that is the repository's (`TR-0.4.3`).
        #expect(defaultValue(of: "plateGrams", on: "EquipmentProfileEntity", in: schema) as? [Int] == [])
        #expect(defaultValue(of: "platePairCounts", on: "EquipmentProfileEntity", in: schema) as? [Int] == [])
    }

    private func defaultValue(of attribute: String, on entity: String, in schema: Schema) -> Any? {
        schema.entities.first { $0.name == entity }?.attributes.first { $0.name == attribute }?.defaultValue
    }
}

// Models that break each constraint on purpose. `G-2.5` is the one requirement whose violation is
// invisible until sync is switched on for real users, so the check that nine entities are held to
// has to be watched failing — the same argument, and the same shape, as `ConventionsGateTests`.

@Model
final class UndefaultedEntity {
    var id: UUID = UUID()
    /// Non-optional with no default: what CoreData refuses first.
    var count: Int

    init(count: Int) { self.count = count }
}

@Model
final class UniqueEntity {
    @Attribute(.unique) var code: String = ""

    init(code: String) { self.code = code }
}

@Model
final class RelatedEntity {
    var id: UUID = UUID()
    var others: [RelatedEntity] = []

    init() {}
}

@Model
final class MintedReferenceEntity {
    var id: UUID = UUID()
    /// A join key defaulting to a minted value instead of the sentinel. Passes `G-2.5`, and is the
    /// realistic way a dangling reference stops being findable — nothing in the compiler or in
    /// `cloudKitViolations` objects to it.
    var otherID: UUID = UUID()

    init() {}
}

@Suite("The CloudKit gate can fail")
struct CloudKitGateTests {
    @Test("A non-optional column with no default is caught, and nothing else is reported")
    func undefaultedIsCaught() {
        let violations = cloudKitViolations(in: Schema([UndefaultedEntity.self]))

        #expect(violations == ["UndefaultedEntity.count is non-optional with no default"])
    }

    @Test("A unique attribute is caught, by both the attribute flag and the entity constraint")
    func uniqueIsCaught() {
        let violations = cloudKitViolations(in: Schema([UniqueEntity.self]))

        #expect(violations == ["UniqueEntity.code is unique", "UniqueEntity declares a uniqueness constraint"])
    }

    @Test("A relationship is caught at all, optional or not")
    func relationshipIsCaught() {
        let violations = cloudKitViolations(in: Schema([RelatedEntity.self]))

        #expect(violations == ["RelatedEntity.others is a relationship"])
    }

    @Test("A join key defaulting to a minted UUID is caught, and is not a G-2.5 violation")
    func mintedJoinKeyIsCaught() {
        // The one finding in this audit that `G-2.5` has nothing to say about: the column is
        // defaulted, so `cloudKitViolations` passes it, and only the sentinel scan objects.
        let schema = Schema([MintedReferenceEntity.self])
        let columns = mintedUUIDColumns(in: schema)

        #expect(cloudKitViolations(in: schema) == [])
        #expect(columns.minted == ["MintedReferenceEntity.otherID"])
        #expect(columns.sentinels == [])
    }
}
