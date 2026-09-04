import Foundation
import SwiftData
import Testing

@testable import Persistence

// The other direction from `SchemaVersioningTests`' backfill suite, and the first time this schema
// has needed it: `TR-16.3` REMOVED `manualWeightGrams` from `TrainingMaxConfigEntity` when the
// number moved to its own table. `SchemaV1`'s three documented rules are all about a column ADDED
// later — nothing said what a store written with a column the declaration no longer has does when
// it is opened.
//
// It is not a hypothetical: `SchemaV1.versionIdentifier` stays `1.0.0` whatever the classes hold
// (that enum's own note says why, and `AppMigrationPlan` has no stages), so a store already on
// disk is reopened by a build whose model shape differs at the SAME version. That is exactly the
// author's own store, which is where a column removal lands first and a clean install never does.
//
// **The probe carries a column the second shape does not declare**, which is what "dropped" means
// here, and the two rows are anchored to the literals written through the first shape.

enum ProbeDropSchemaBefore: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [ProbeDroppedRow.self] }

    @Model
    final class ProbeDroppedRow {
        var id: UUID = UUID()
        var label: String = ""

        /// The column the later shape does not declare — `manualWeightGrams`' stand-in, optional
        /// and `Int?` for the same reason the real one was.
        var retiredGrams: Int?

        init(id: UUID = UUID(), label: String, retiredGrams: Int?) {
            self.id = id
            self.label = label
            self.retiredGrams = retiredGrams
        }
    }
}

enum ProbeDropSchemaAfter: VersionedSchema {
    /// **The same identifier as ``ProbeDropSchemaBefore``**, which is the whole point: this models
    /// what shipping a narrower class at an unchanged version does, not what a staged migration
    /// does.
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [ProbeDroppedRow.self] }

    /// ``ProbeDropSchemaBefore/ProbeDroppedRow`` less its retired column.
    @Model
    final class ProbeDroppedRow {
        var id: UUID = UUID()
        var label: String = ""

        init(id: UUID = UUID(), label: String) {
            self.id = id
            self.label = label
        }
    }
}

@Suite("A store survives a column being dropped from its live version")
struct SchemaDroppedColumnTests {
    @Test("Rows written with a column the declaration no longer has still open, whole")
    func aDroppedColumnLeavesItsRowsIntact() throws {
        let alpha = UUID()
        let beta = UUID()

        try withTemporaryStore { url in
            // Scoped so the first container is released before the second opens the same file —
            // `noOpMigrationPreservesData`'s hygiene, and its reason.
            try {
                let context = try makeMigratedContext(
                    schema: Schema(versionedSchema: ProbeDropSchemaBefore.self),
                    url: url,
                    plan: nil
                )
                context.insert(
                    ProbeDropSchemaBefore.ProbeDroppedRow(
                        id: alpha, label: "alpha", retiredGrams: 180_000))
                context.insert(
                    ProbeDropSchemaBefore.ProbeDroppedRow(
                        id: beta, label: "beta", retiredGrams: nil))
                try context.save()
            }()

            // `plan: nil`, because that is what the app does: `AppMigrationPlan` has no stage that
            // could name this, and a store opened by the shipping build gets no help from one.
            let reopened = try makeMigratedContext(
                schema: Schema(versionedSchema: ProbeDropSchemaAfter.self),
                url: url,
                plan: nil
            )
            let rows = try reopened.fetch(FetchDescriptor<ProbeDropSchemaAfter.ProbeDroppedRow>())

            // Anchored to the literals written above rather than to a re-read: two empty fetches
            // agree with each other, and "the rows are gone" is precisely the failure this is for.
            #expect(rows.map(\.label).sorted() == ["alpha", "beta"])
            #expect(Set(rows.map(\.id)) == Set([alpha, beta]))
        }
    }
}
