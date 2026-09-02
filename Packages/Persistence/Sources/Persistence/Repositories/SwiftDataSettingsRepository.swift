import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData

/// Serialises the settings row's find-or-create across every repository in the process.
///
/// **An actor serialises its own calls and nothing else, which is not enough for this one row.**
/// Two `SwiftDataSettingsRepository` instances over one container — two `PersistenceStack`s, one for
/// the app and one for an export or a preview — each hold their own `ModelContext`, so both can
/// observe an empty store and both insert. Measured: 8 of 8 concurrent attempts produced two rows
/// carrying two different `userID`s. That is the outcome `TR-1.10` exists to prevent and the one
/// this layer cannot repair afterwards, `userID` having no setter.
///
/// Held across the fetch **and** the insert, because it is the gap between them that forks the
/// identity. Nothing suspends inside the critical section — the repository's methods are
/// synchronous — so the lock cannot be held across an `await`.
private let settingsBootstrapLock = NSLock()

/// `SettingsRepository` over SwiftData (`TR-0.4.2`, `TR-0.3.8`, `TR-1.10`).
@ModelActor
actor SwiftDataSettingsRepository: SettingsRepository {
    /// The settings row, minting one only when the store holds none — the half of `TR-1.10`'s
    /// "generated once" no schema can hold.
    ///
    /// **The search includes soft-deleted rows, and that is the whole safety of it.** This protocol
    /// has no delete, so a deleted settings row can only have arrived from elsewhere; filtering it
    /// out would turn find-or-create into create and mint a *second* anonymous identity beside one
    /// the store already has. `FR-5.1.2` claims the user's local data under that id, so the two
    /// failures are not symmetric: returning a row somebody deleted is visible and reversible,
    /// forking the identity is neither. `UserSettingsEntity.userID` has no setter, so this layer
    /// cannot repair a second row afterwards — only decline to create it.
    ///
    /// **Two rows already there resolve by rule 2 and no third is created.** Nothing is repaired
    /// and nothing is merged: the loser keeps its own id, where a merge would silently retire an
    /// identity that some other device is still writing under.
    ///
    /// The values a new row is created with are first-launch choices rather than schema defaults.
    /// They coincide with `SchemaDefaults` by argument and not by identity — that type is what an
    /// *absent* column holds, and its own note says nothing in schema v1 ever reaches it, which
    /// would stop being true if the bootstrap read from it.
    func settings() throws -> UserSettings {
        settingsBootstrapLock.lock()
        defer { settingsBootstrapLock.unlock() }

        let existing = try modelContext.rows(UserSettingsEntity.self, includingDeleted: true)
        if let settings = resolved(existing) { return settings.record }

        let created = UserSettingsEntity(
            userID: UUID(),
            displayUnit: .kilograms,
            e1RMFormula: .defaultFormula,
            // G-7.1's dark is what the app adopts before the user has expressed a preference,
            // and `.system` is a preference — a lifter who picks it is asking to follow the
            // device. A first-launch row saying `.system` would make the two indistinguishable.
            theme: .dark,
            defaultRoundingIncrementGrams: 2500,
            defaultRoundingStrategy: .nearest,
            displayPrecisionMilliUnits: nil,
            e1RMLookbackDays: UserSettings.defaultE1RMLookbackDays,
            keepScreenAwake: UserSettings.defaultKeepScreenAwake
        )
        modelContext.insert(created)
        try modelContext.saveStamped()
        return created.record
    }

    /// Replaces the stored preferences, refusing a record that carries a different identity.
    ///
    /// The comparison is against the row ``settings()`` returns, not against every row: two rows
    /// disagreeing about `userID` is a store this layer cannot repair, and checking them all would
    /// make it a store where preferences can no longer be saved either.
    ///
    /// A save into an empty store inserts, honouring the record's `userID` — nothing is in force,
    /// so writing the record's is the mint rather than a rewrite.
    ///
    /// **This is the one save that does not key on the record's `id`**, and it is the only save
    /// whose row is a singleton. `ModelContext.upsert(_:as:)` would insert a second settings row
    /// for a record built with a fresh id — a caller assembling one from defaults rather than from
    /// ``settings()`` — which is the exact outcome ``settings()`` goes out of its way to avoid one
    /// method above. Writing the existing rows instead keeps their own ids, and `update(from:)`
    /// does not touch `id` or `userID`, so neither identity moves.
    func save(_ settings: UserSettings) throws {
        try write(settings, refusingAForeignIdentity: true)
    }

    /// Writes a backup's preferences onto the row in force. See the protocol for the rule.
    ///
    /// **The refusal is the only thing this drops**, which is what makes the two the same write
    /// with one clause between them rather than two writers that could drift: `update(from:)`
    /// declines to touch `id` or `userID` whichever way it was reached, so the identity cannot move
    /// down this path either.
    func restorePreferences(from backup: UserSettings) throws {
        try write(backup, refusingAForeignIdentity: false)
    }

    /// The settings row's one write, with or without the identity guard.
    ///
    /// - Parameters:
    ///   - settings: The record to write.
    ///   - refusingAForeignIdentity: Whether a record naming a different `userID` is refused —
    ///     `true` for ``save(_:)``, `false` for ``restorePreferences(from:)``.
    /// - Throws: ``RepositoryInterface/RepositoryError/identityAlreadyEstablished(recordID:)``, or
    ///   whatever the store throws.
    private func write(_ settings: UserSettings, refusingAForeignIdentity: Bool) throws {
        // The bootstrap's lock, because this method also inserts when the store is empty — a
        // restore racing a first launch forks the identity exactly as two bootstraps would.
        settingsBootstrapLock.lock()
        defer { settingsBootstrapLock.unlock() }

        let existing = try modelContext.rows(UserSettingsEntity.self, includingDeleted: true)
        guard let inForce = resolved(existing) else {
            modelContext.insert(UserSettingsEntity(record: settings))
            try modelContext.saveStamped()
            return
        }
        if refusingAForeignIdentity, inForce.userID != settings.userID {
            throw RepositoryError.identityAlreadyEstablished(recordID: settings.id)
        }

        for row in existing { row.update(from: settings) }
        try modelContext.saveStamped()
    }
}
