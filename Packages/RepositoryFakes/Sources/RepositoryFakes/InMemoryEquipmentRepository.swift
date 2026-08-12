import Foundation
import RepositoryInterface

/// `EquipmentRepository` over a dictionary (`TR-0.4.2`).
struct InMemoryEquipmentRepository: EquipmentRepository, Sendable {
    let store: InMemoryRepositoryStore

    /// Every profile, by name then id.
    func profiles(includingDeleted: Bool) async throws -> [EquipmentProfile] {
        await store.allProfiles(includingDeleted: includingDeleted)
    }

    /// The profile carrying `id`, or `nil`.
    func profile(id: UUID, includingDeleted: Bool) async throws -> EquipmentProfile? {
        await store.profile(id: id, includingDeleted: includingDeleted)
    }

    /// The live profile carrying the default flag.
    func defaultProfile() async throws -> EquipmentProfile? {
        await store.defaultProfile()
    }

    /// Inserts or replaces the profile, refusing plate lists that cannot describe a gym.
    func save(_ profile: EquipmentProfile) async throws {
        try await store.saveProfile(profile)
    }

    /// Marks one profile the default and clears every other, in one write.
    func makeDefault(profileID: UUID) async throws {
        try await store.makeDefault(profileID: profileID)
    }

    /// Soft-deletes the profile.
    func deleteProfile(id: UUID) async throws {
        try await store.deleteProfile(id: id)
    }
}

extension InMemoryRepositoryStore {
    /// Every profile a read may return, ordered by name then id.
    func allProfiles(includingDeleted: Bool) -> [EquipmentProfile] {
        profiles.values
            .live(includingDeleted: includingDeleted)
            .sortedDeterministically { ($0.name, $0.id.uuidString) }
    }

    /// The profile carrying `id`, subject to the flag.
    func profile(id: UUID, includingDeleted: Bool) -> EquipmentProfile? {
        profiles[id].flatMap { includingDeleted || !$0.isSoftDeleted ? $0 : nil }
    }

    /// The live profile carrying the flag.
    ///
    /// The read does not repair the store — clearing a second claimant here would make a display
    /// call a write, and ``makeDefault(profileID:)`` is the only writer of that column.
    func defaultProfile() -> EquipmentProfile? {
        profiles.values
            .filter(\.isDefault)
            .live(includingDeleted: false)
            .max { ($0.updatedAt, $0.id.uuidString) < ($1.updatedAt, $1.id.uuidString) }
    }

    /// Inserts or replaces `profile`, refusing one whose plate lists cannot describe a gym.
    ///
    /// **The one save that projects before it writes.** A profile is *authored* here, and a record
    /// does not validate — so without this a repeated denomination would be stored happily and fail
    /// much later, inside `PlateCalculator`, on a screen far from the one that wrote it. A read
    /// still returns a malformed profile whole.
    ///
    /// **`isDefault` is not honoured**: on insert it is cleared, on update the stored row keeps
    /// what it had. "Exactly one default" is a cross-row invariant and no single row's save can
    /// hold it.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/unusableRecord(recordID:reason:)`` when
    ///   `EquipmentProfile.inventory()` refuses the two plate lists.
    func saveProfile(_ profile: EquipmentProfile) throws {
        do {
            _ = try profile.inventory()
        } catch {
            throw RepositoryError.unusableRecord(recordID: profile.id, reason: error)
        }
        let stored = profiles[profile.id]
        upserted(
            profile.claiming(isDefault: stored?.isDefault ?? false), into: &profiles, at: .now)
    }

    /// Marks one profile the default and clears every other, in one write.
    ///
    /// **Only live rows are cleared**, because `defaultProfile()` reads live rows and stamping a row
    /// the user deleted is a write with no reader. **And only rows whose flag actually moves are
    /// written**, which is not an optimisation: `updatedAt` is `G-2.4`'s conflict key, so a no-op
    /// local write would outrank a real edit made on another device and revert it silently.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/recordNotFound(id:)`` when no live profile
    ///   carries `profileID`.
    func makeDefault(profileID: UUID) throws {
        let live = profiles.values.live(includingDeleted: false)
        guard live.contains(where: { $0.id == profileID }) else {
            throw RepositoryError.recordNotFound(id: profileID)
        }

        let now = Date.now
        for profile in live where profile.isDefault != (profile.id == profileID) {
            profiles[profile.id] =
                profile
                .claiming(isDefault: profile.id == profileID)
                .stamped(
                    createdAt: profile.createdAt, updatedAt: now, deletedAt: profile.deletedAt)
        }
    }

    /// Soft-deletes the profile.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/recordNotFound(id:)`` when no live profile
    ///   carries `id`.
    func deleteProfile(id: UUID) throws {
        try softDelete(id: id, in: &profiles, at: .now)
    }
}
