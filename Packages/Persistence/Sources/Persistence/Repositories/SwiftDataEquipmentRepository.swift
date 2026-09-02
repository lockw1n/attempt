import Foundation
import RepositoryInterface
import SwiftData

/// `EquipmentRepository` over SwiftData (`TR-0.4.2`, `FR-1.4.2`, `FR-1.10.3`).
@ModelActor
actor SwiftDataEquipmentRepository: EquipmentRepository {
    func profiles(includingDeleted: Bool) throws -> [EquipmentProfile] {
        try modelContext.rows(EquipmentProfileEntity.self, includingDeleted: includingDeleted)
            .sortedDeterministically { ($0.name, $0.id.uuidString) }
            .map(\.record)
    }

    func profile(id: UUID, includingDeleted: Bool) throws -> EquipmentProfile? {
        try modelContext.row(
            EquipmentProfileEntity.self, id: id, includingDeleted: includingDeleted)?.record
    }

    /// The live profile carrying the flag, by rule 2 when more than one does.
    ///
    /// The read does not repair the store — clearing the loser here would make a display call a
    /// write, and `makeDefault(profileID:)` is the only writer of that column.
    func defaultProfile() throws -> EquipmentProfile? {
        let marked = try modelContext.rows(
            EquipmentProfileEntity.self,
            matching: #Predicate { $0.isDefault },
            includingDeleted: false
        )
        return resolved(marked)?.record
    }

    /// Inserts or replaces the profile, refusing one whose plate lists cannot describe a gym.
    ///
    /// **The one save that projects before it writes.** A profile is *authored* here, and the raw
    /// plate writer the record shape needs removed the only structural refusal the write path had —
    /// so without this, a repeated denomination would be stored happily and fail much later, inside
    /// `PlateCalculator`, on a screen far from the one that wrote it. A read still returns a
    /// malformed profile whole, and `FR-1.11.3`'s restore still writes one: tolerating a corrupt row
    /// is what the record shape is for.
    ///
    /// **`isDefault` is cleared on insert rather than honoured.** The mapping's `update(from:)`
    /// already declines to write it, and `init(record:)` carries it like every other column, so the
    /// save path has to say no itself — or a record could claim the flag beside a profile that
    /// already holds it. "Exactly one default" is a cross-row invariant and
    /// ``makeDefault(profileID:)`` is where it lives, which is also how `FR-1.11.3`'s restore gets
    /// the flag back: it writes the profiles, then names the one the file marked.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/unusableRecord(recordID:reason:)`` if
    ///   `EquipmentProfile.inventory()` refuses the two plate lists.
    func save(_ profile: EquipmentProfile) throws {
        do {
            _ = try profile.inventory()
        } catch {
            throw RepositoryError.unusableRecord(recordID: profile.id, reason: error)
        }

        try modelContext.upsert(profile, as: EquipmentProfileEntity.self) { $0.isDefault = false }
        try modelContext.saveStamped()
    }

    /// Marks one profile the default and clears every other, in one write.
    ///
    /// **Only live rows are cleared.** `defaultProfile()` reads live rows, so the flag on a deleted
    /// profile is unreachable — and stamping `updatedAt` on a row the user deleted is a write with
    /// no reader, which under sync is the shape that resurrects things.
    ///
    /// **Only rows whose flag actually moves are assigned**, which is not an optimisation.
    /// Assigning a `@Model` property marks the row changed whatever the value was — measured — so
    /// `saveStamped` would restamp `updatedAt` on every other profile in the store. `updatedAt` is
    /// `G-2.4`'s conflict key, so a no-op local write would outrank a real edit made on another
    /// device and silently revert it. Same reason the cascade skips rows it would not change.
    func makeDefault(profileID: UUID) throws {
        let profiles = try modelContext.rows(EquipmentProfileEntity.self, includingDeleted: false)
        guard profiles.contains(where: { $0.id == profileID }) else {
            throw RepositoryError.recordNotFound(id: profileID)
        }

        for profile in profiles where profile.isDefault != (profile.id == profileID) {
            profile.isDefault = profile.id == profileID
        }
        try modelContext.saveStamped()
    }

    func deleteProfile(id: UUID) throws {
        let profiles = try modelContext.rows(
            EquipmentProfileEntity.self, id: id, includingDeleted: false)
        guard !profiles.isEmpty else { throw RepositoryError.recordNotFound(id: id) }

        let now = Date.now
        for profile in profiles { profile.markDeleted(at: now) }
        try modelContext.saveStamped(at: now)
    }
}
