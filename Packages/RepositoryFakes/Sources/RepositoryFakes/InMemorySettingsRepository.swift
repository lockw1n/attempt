import Foundation
import PowerliftingCore
import RepositoryInterface

/// `SettingsRepository` over one optional row (`TR-0.4.2`, `TR-1.10`).
struct InMemorySettingsRepository: SettingsRepository, Sendable {
    let store: InMemoryRepositoryStore

    /// The settings row, minting one only when the store holds none.
    func settings() async throws -> UserSettings {
        await store.settings()
    }

    /// Replaces the stored preferences, refusing a record that carries a different identity.
    func save(_ settings: UserSettings) async throws {
        try await store.saveSettings(settings)
    }
}

extension InMemoryRepositoryStore {
    /// The settings row, created on first call and stable afterwards.
    ///
    /// **One slot rather than a table, which is the singleton made structural.** `TR-1.10`'s
    /// "generated once" is the half no schema can hold, and `FR-5.1.2` claims the user's local data
    /// under `userID` — so a second row is the outcome this method exists to prevent and the one
    /// that cannot be repaired afterwards.
    ///
    /// The values a new row is created with are first-launch choices rather than schema defaults;
    /// they coincide with the store side's by argument and not by identity.
    func settings() -> UserSettings {
        if let existing = settingsRow { return existing }
        let now = Date.now
        let created = UserSettings(
            id: UUID(),
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            userID: UUID(),
            displayUnit: .kilograms,
            e1RMFormula: .defaultFormula,
            // G-7.1's dark is what the app adopts before the user has expressed a preference,
            // and `.system` is a preference — a lifter who picks it is asking to follow the
            // device. A first-launch row saying `.system` would make the two indistinguishable.
            theme: .dark,
            defaultRoundingIncrement: Weight(grams: 2500),
            defaultRoundingStrategy: .nearest,
            displayPrecision: nil,
            e1RMLookbackDays: UserSettings.defaultE1RMLookbackDays,
            keepScreenAwake: UserSettings.defaultKeepScreenAwake
        )
        settingsRow = created
        return created
    }

    /// Writes `settings`'s preferences onto the row that is already there.
    ///
    /// **Neither `id` nor `userID` moves**, which is why this is not an upsert: a caller assembling
    /// a record from defaults rather than from ``settings()`` would otherwise replace the identity
    /// the app has been writing under. A save into an empty store inserts and honours the record's
    /// own `userID` — that is `FR-1.11.3`'s restore, the one caller with an identity to reinstate
    /// rather than to mint.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/identityAlreadyEstablished(recordID:)`` when
    ///   the record names a different `userID` from the stored row's.
    func saveSettings(_ settings: UserSettings) throws {
        let now = Date.now
        guard let inForce = settingsRow else {
            settingsRow = settings.stamped(
                createdAt: settings.createdAt, updatedAt: now, deletedAt: nil)
            return
        }
        guard inForce.userID == settings.userID else {
            throw RepositoryError.identityAlreadyEstablished(recordID: settings.id)
        }
        settingsRow =
            settings
            .preferencesWritten(onto: inForce)
            .stamped(createdAt: inForce.createdAt, updatedAt: now, deletedAt: inForce.deletedAt)
    }
}
