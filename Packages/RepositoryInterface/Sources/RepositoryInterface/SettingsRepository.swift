import Foundation
import PowerliftingCore

/// The single settings row, and the anonymous identity on it (`TR-0.4.1`, `TR-0.3.8`, `TR-1.10`).
///
/// **The only protocol here with no `includingDeleted:` parameter and no delete.** A soft-deleted
/// settings row would be a user whose identity had been withdrawn, which no requirement describes;
/// offering the read would make it look like a state the app supports.
public protocol SettingsRepository: Sendable {
    /// The user's settings, creating the row on first call.
    ///
    /// **Find-or-create, never create, and there is deliberately no separate bootstrap method to
    /// call twice.** `TR-1.10` generates the anonymous user id **once**, on first launch, and
    /// nothing in the schema can hold that: `G-2.5` forbids unique constraints and no store
    /// enforces a cross-row predicate, so two settings rows carrying two different ids are
    /// representable — demonstrated by test against the real store. A bootstrap that inserted
    /// unconditionally would mint a second anonymous identity on some later launch, and `FR-5.1.2`
    /// would then claim the user's local data under whichever one the tiebreak favoured. The stored
    /// id has no writer, so this layer cannot repair a second row afterwards — only avoid creating
    /// it.
    ///
    /// If two rows already exist, this returns one of them by the tiebreak in this module's header
    /// and does not create a third.
    func settings() async throws -> UserSettings

    /// Replaces the stored preferences (`FR-1.10.1`, `FR-1.10.2`).
    ///
    /// - Throws: ``RepositoryError/identityAlreadyEstablished(recordID:)`` if
    ///   ``UserSettings/userID`` differs from the stored one.
    func save(_ settings: UserSettings) async throws

    /// Writes a backup's preferences onto the row already in force (`FR-1.11.3`).
    ///
    /// **The identity in force wins, and the file's is honoured only where there is none.** That is
    /// `TR-1.10` read exactly — the id is minted once and never *re*written — and it is the only
    /// reading under which both requirements hold. A backup taken on one device and restored onto
    /// another arrives after that device has already bootstrapped, so there is always an identity in
    /// force by the time a restore is reachable at all; adopting the file's would hand `FR-5.1.2`
    /// two devices claiming one identity, and refusing would fail the restore's last write with
    /// every other table already landed. What the lifter gets back is what they can name — unit,
    /// precision, formula, lookback, rounding, theme, keep-awake, dashboard picks — and the rows
    /// those preferences describe stay claimed under this device's id, which is where they are.
    ///
    /// **A separate member rather than a flag on ``save(_:)``**, because the two are different acts.
    /// An arbitrary caller carrying a foreign id is a stale or hand-assembled record and is still
    /// refused; widening `save(_:)` would retire that invariant instead of qualifying it.
    ///
    /// - Parameter backup: The settings row a backup file carries.
    func restorePreferences(from backup: UserSettings) async throws
}
