import Foundation
import RepositoryInterface
import SeedContent

/// Puts the seed catalogue into the exercise repository (`TR-0.5.1`, `NFR-1.7`).
///
/// **Safe to run on every launch.** An import is a merge, not an insert: a second run over the same
/// catalogue performs no writes at all, and one over a newer catalogue writes only the rows that
/// moved. See this module's header for which columns the seed owns and which belong to the row.
public struct SeedImporter: Sendable {
    private let repository: any ExerciseRepository

    /// An importer writing into `exercises`.
    public init(exercises repository: any ExerciseRepository) {
        self.repository = repository
    }

    /// Imports the catalogue this app ships, from the bundle and with no network (`NFR-1.7`).
    ///
    /// The one call a launch makes. `BundledCatalogue` is what knows where the payload sits — a
    /// second implementation of that lookup is a second place for a packaging change to break it,
    /// with nothing loading the real file to notice.
    ///
    /// - Parameter now: What a newly written row records as its `createdAt`.
    /// - Returns: What the import did.
    /// - Throws: ``SeedImportError/invalidPayload(_:)`` if the shipped file does not validate, which
    ///   is a packaging fault rather than a runtime condition.
    @discardableResult
    public func importBundledCatalogue(at now: Date = Date()) async throws -> SeedImportSummary {
        try await importCatalogue(
            from: BundledCatalogue.data(),
            minimumExercises: BundledCatalogue.minimumExercises,
            at: now)
    }

    /// Imports a payload's bytes, having validated them.
    ///
    /// **Nothing is written until the whole payload validates.** A half-applied catalogue is the
    /// state `NFR-1.7` has no recovery from — first launch after install, in airplane mode — so the
    /// check is one pass over the document rather than a refusal per entry.
    ///
    /// - Parameters:
    ///   - data: The payload's bytes, from the bundle or from `TR-0.5.3`'s fetcher.
    ///   - minimumExercises: How many entries the caller requires. **Deliberately without a
    ///     default**, unlike the validator it forwards to: `TR-0.5.1` puts the floor at eighty and a
    ///     caller that has not thought about it is likelier to want that than to want one. A fetched
    ///     payload short enough to matter is exactly what `TR-0.5.3` has to refuse.
    ///   - now: What a newly written row records as its `createdAt`.
    /// - Returns: What the import did.
    /// - Throws: ``SeedImportError/invalidPayload(_:)`` with every reason the validator found, or
    ///   whatever the repository raises once writing has begun.
    @discardableResult
    public func importCatalogue(
        from data: Data,
        minimumExercises: Int,
        at now: Date = Date()
    ) async throws -> SeedImportSummary {
        let failures = SeedCatalogueValidator.validate(data, minimumExercises: minimumExercises)
        guard failures.isEmpty else { throw SeedImportError.invalidPayload(failures) }

        // Decoded a second time on purpose: the validator decodes in order to check and hands back
        // failures rather than a value, and its `Data` entry point is the only one that can report
        // the three faults a value built in Swift cannot express. A decode of 116 entries is nothing
        // beside the writes that follow.
        let catalogue = try JSONDecoder().decode(SeedCatalogue.self, from: data)
        return try await apply(catalogue, at: now)
    }

    /// Merges a validated catalogue into the store.
    private func apply(_ catalogue: SeedCatalogue, at now: Date) async throws -> SeedImportSummary {
        // ONE READ, NOT ONE PER ENTRY. This runs on first launch, which `NFR-1.1` gives 1.5 s in
        // total, and the catalogue is 116 entries — a lookup per entry is 116 round trips for rows
        // this list already holds. Read before the writes, so the sweep below is over the rows this
        // import did not put there. `includingDeleted:` is `true` because it is the widest read the
        // protocol offers and a merge that missed a row would insert a second copy of it;
        // `ExerciseRepository` has no delete at all and says so, which is what makes the flag free
        // rather than load-bearing.
        let storedBefore = try await repository.exercises(includingDeleted: true)
        var storedByID: [UUID: Exercise] = [:]
        var duplicatedIDs: Set<UUID> = []
        for row in storedBefore where storedByID.updateValue(row, forKey: row.id) != nil {
            duplicatedIDs.insert(row.id)
        }
        var inserted = 0
        var updated = 0
        var unchanged = 0
        var seeded: Set<UUID> = []

        for entry in SeedExerciseOrdering.parentsFirst(catalogue.exercises) {
            seeded.insert(entry.id)
            // `G-2.5` forbids the unique constraint that would stop two rows sharing an id, and
            // which of the pair wins is the repository's rule — so an id carried by more than one
            // row is asked for by id, and nothing here invents a second answer. Every other id,
            // which on any real launch is all of them, is already in hand. Safe against the loop's
            // own writes because `SeedCatalogueValidator` refuses a repeated id, so no entry is
            // visited twice.
            let existing: Exercise?
            if duplicatedIDs.contains(entry.id) {
                existing = try await repository.exercise(id: entry.id, includingDeleted: true)
            } else {
                existing = storedByID[entry.id]
            }
            guard let existing else {
                try await repository.save(.seeded(from: entry, at: now))
                inserted += 1
                continue
            }
            // `Exercise.isCustom` decides whether an import may overwrite the row, and it says so on
            // itself. A user's own exercise is not the seed's to correct.
            guard !existing.isCustom else {
                unchanged += 1
                continue
            }
            let merged = existing.reseeded(from: entry)
            guard merged != existing else {
                unchanged += 1
                continue
            }
            try await repository.save(merged)
            updated += 1
        }

        let archived = try await archiveRemovals(notIn: seeded, from: storedBefore)
        return SeedImportSummary(
            inserted: inserted, updated: updated, archived: archived, unchanged: unchanged)
    }

    /// Archives the built-ins the catalogue no longer lists (`FR-1.1.5`, `G-1.3`).
    ///
    /// A row already archived is left alone rather than re-archived, which is what keeps a second
    /// run free of writes. Custom rows are skipped: an exercise the user authored was never in the
    /// catalogue, so its absence from one says nothing.
    ///
    /// `deletedAt` is not consulted, and that is a decision rather than an omission: ``ExerciseRepository``
    /// has no delete, so a guard for it would be a branch no call could reach. Two rows sharing an
    /// id are archived as two rows, because there is no reading under which one of the pair should
    /// stay in the pickers.
    private func archiveRemovals(notIn seeded: Set<UUID>, from stored: [Exercise]) async throws -> Int {
        var archived = 0
        for row in stored where !seeded.contains(row.id) && !row.isCustom && !row.isArchived {
            try await repository.save(row.archived())
            archived += 1
        }
        return archived
    }
}
