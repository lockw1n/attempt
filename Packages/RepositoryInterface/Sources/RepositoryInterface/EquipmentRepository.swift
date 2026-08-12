import Foundation
import PowerliftingCore

/// The user's equipment profiles (`TR-0.4.1`, `FR-1.4.2`, `FR-1.4.3`, `FR-1.10.3`).
public protocol EquipmentRepository: Sendable {
    /// Every profile, in ``EquipmentProfile/name`` order (`FR-1.10.3`).
    func profiles(includingDeleted: Bool) async throws -> [EquipmentProfile]

    /// One profile, or `nil` if no row carries that id.
    func profile(id: UUID, includingDeleted: Bool) async throws -> EquipmentProfile?

    /// The profile the plate calculator reaches for, or `nil` if none is marked.
    ///
    /// `nil` is a real answer rather than a failure: a user who has configured no gym has no
    /// inventory, and `FR-1.4.1`'s per-side loading simply has nothing to show. Nothing is
    /// invented — a default bar and plate set would be a data claim `G-6.2` wants cited.
    ///
    /// Two profiles may both be marked; the tiebreak in this module's header decides which is
    /// returned, and the read does not repair the store.
    ///
    /// **No `includingDeleted:`, and it is not an omission.** A deleted profile is a gym the user
    /// left, so it cannot be the one the calculator reaches for — see
    /// ``deleteProfile(id:)``, which leaves no default rather than promoting another.
    /// ``profiles(includingDeleted:)`` is where deleted profiles are reachable.
    func defaultProfile() async throws -> EquipmentProfile?

    /// Inserts or replaces the profile, keyed on ``EquipmentProfile/id`` (`FR-1.4.2`).
    ///
    /// **``EquipmentProfile/isDefault`` is not written by this**, whatever the record carries. Use
    /// ``makeDefault(profileID:)``: "exactly one default" is a cross-row invariant, and a save that
    /// honoured the flag would let two profiles claim it in two separate writes with nothing
    /// noticing.
    func save(_ profile: EquipmentProfile) async throws

    /// Makes one profile the default and clears the flag on every other, in one write.
    ///
    /// - Throws: ``RepositoryError/recordNotFound(id:)`` if no live profile carries that id.
    func makeDefault(profileID: UUID) async throws

    /// Soft-deletes one profile.
    ///
    /// Deleting the default leaves no default rather than promoting another: which gym a lifter
    /// uses next is not derivable, and `FR-1.4.1` degrades to showing no loading, which is
    /// recoverable in one tap.
    ///
    /// - Throws: ``RepositoryError/recordNotFound(id:)`` if no live profile carries that id.
    func deleteProfile(id: UUID) async throws
}
