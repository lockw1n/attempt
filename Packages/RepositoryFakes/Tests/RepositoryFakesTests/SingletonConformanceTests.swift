import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

/// The two invariants that are facts about a *set* of rows rather than about any one of them: the
/// settings singleton (`TR-1.10`) and the single default equipment profile (`FR-1.10.3`).
///
/// Neither can be held by a record, so neither can be held by a save — which is why both are places
/// a fake storing what it is handed goes wrong in a way no signature shows.
@Suite("Conformance — the two cross-row invariants")
struct SingletonConformanceTests {
    @Test("settings() mints one identity and returns it thereafter", arguments: Subject.all)
    func theIdentityIsGeneratedOnce(_ subject: Subject) async throws {
        let repositories = try subject.make()

        let first = try await repositories.settings.settings()
        let second = try await repositories.settings.settings()

        #expect(first.userID == second.userID)
        #expect(first.id == second.id)
    }

    @Test("A save edits the row that is there rather than replacing its identity", arguments: Subject.all)
    func aSaveKeepsTheStoredIdentity(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let stored = try await repositories.settings.settings()

        // A caller assembling a record from defaults rather than from `settings()` — same user,
        // fresh row id. The stored row keeps its own `id`; only the preferences move.
        let rebuilt = UserSettings(
            id: UUID(),
            createdAt: fixtureCreatedAt,
            updatedAt: fixtureUpdatedAt,
            deletedAt: nil,
            userID: stored.userID,
            displayUnit: .pounds,
            e1RMFormula: stored.e1RMFormula,
            theme: .dark,
            defaultRoundingIncrement: Weight(grams: 5000),
            defaultRoundingStrategy: .down
        )
        try await repositories.settings.save(rebuilt)

        let after = try await repositories.settings.settings()
        #expect(after.id == stored.id)
        #expect(after.userID == stored.userID)
        #expect(after.displayUnit == .pounds)
        #expect(after.theme == .dark)
        #expect(after.defaultRoundingIncrement == Weight(grams: 5000))
        #expect(after.createdAt == stored.createdAt)
        // Against the literal the record carried, not against `stored.updatedAt`: the two could
        // legitimately land in the same instant, and `a >= b` on two values the code produced is
        // the shape that cannot fail.
        #expect(after.updatedAt > fixtureUpdatedAt)
    }

    @Test("A save carrying a different userID is refused", arguments: Subject.all)
    func theIdentityCannotBeMoved(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let stored = try await repositories.settings.settings()
        let foreign = UserSettings(
            id: stored.id,
            createdAt: stored.createdAt,
            updatedAt: stored.updatedAt,
            deletedAt: nil,
            userID: UUID(),
            displayUnit: .pounds,
            e1RMFormula: stored.e1RMFormula,
            theme: stored.theme,
            defaultRoundingIncrement: stored.defaultRoundingIncrement,
            defaultRoundingStrategy: stored.defaultRoundingStrategy
        )

        await #expect(throws: RepositoryError.identityAlreadyEstablished(recordID: foreign.id)) {
            try await repositories.settings.save(foreign)
        }
        #expect(try await repositories.settings.settings().userID == stored.userID)
        #expect(try await repositories.settings.settings().displayUnit == stored.displayUnit)
    }

    /// `FR-1.11.3`'s restore, and the one caller with an identity to reinstate rather than to mint.
    ///
    /// **The record carries a `deletedAt`, and that is the point of the fixture.** Rule 7 says a
    /// save ignores it, and no writer in this layer reinstates a soft-deleted row — gap §32 records
    /// that as a known limit of the restore rather than an accident. Without a `deletedAt` here the
    /// clause was never exercised and both implementations agreed only by two independent `nil`s:
    /// a probe that made this path honour the record's `deletedAt` left the whole suite green, and
    /// the result would have been a restore that inserts a settings row the app reads as deleted,
    /// under a `userID` that has no setter to repair it with.
    @Test("A save into an empty store honours the identity it carries", arguments: Subject.all)
    func aRestoreReinstatesTheIdentity(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let restored = UUID()
        try await repositories.settings.save(
            settingsRecord(userID: restored, deletedAt: Date(timeIntervalSince1970: 0)))

        let after = try await repositories.settings.settings()
        #expect(after.userID == restored)
        #expect(after.displayUnit == .pounds)
        #expect(after.createdAt == fixtureCreatedAt)
        #expect(after.deletedAt == nil)
    }

    /// `FR-1.11.3`'s restore onto a device that has already bootstrapped — the case the shipping
    /// app is always in, and the one `save(_:)` refuses.
    ///
    /// **The comparison is one equality against a record built by ``RepositoryInterface/UserSettings/carryingPreferences(of:)``**,
    /// which is field-for-field rather than a hand-picked three: this record has gained columns
    /// twice, and a list of preferences written out here would agree with a restore that had
    /// quietly stopped carrying the next one. `updatedAt` is neutralised because the write stamps
    /// it (rule 7) and `AuditColumnConformanceTests` is where that claim lives.
    ///
    /// The incoming record carries a `deletedAt`, so rule 7's "a save ignores it" is exercised on
    /// this path too — a restore that honoured it would leave the device holding a settings row the
    /// app reads as deleted, under an identity with no setter to repair it with.
    @Test("A restore keeps the identity in force and takes the file's preferences", arguments: Subject.all)
    func aRestoreKeepsTheIdentityInForce(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let stored = try await repositories.settings.settings()
        let incoming = foreignBackupSettings()

        try await repositories.settings.restorePreferences(from: incoming)

        let after = try await repositories.settings.settings()
        // Explicitly, and from both directions: the device's id stayed and the file's did not land.
        #expect(after.userID == stored.userID)
        #expect(after.userID != incoming.userID)
        #expect(after.id == stored.id)
        #expect(after.createdAt == stored.createdAt)

        var expected = stored.carryingPreferences(of: incoming)
        expected.updatedAt = after.updatedAt
        #expect(after == expected)
    }

    /// The other half of the rule: where no identity is in force, the file's is honoured — that is
    /// the mint rather than a rewrite, and it is what makes `DOD-1.3`'s wipe-and-restore lossless
    /// over this table as well as the other eleven.
    @Test("A restore into an empty store honours the identity it carries", arguments: Subject.all)
    func aRestoreIntoAnEmptyStoreReinstatesTheIdentity(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let incoming = foreignBackupSettings()

        try await repositories.settings.restorePreferences(from: incoming)

        let after = try await repositories.settings.settings()
        #expect(after.userID == incoming.userID)
        #expect(after.id == incoming.id)
        #expect(after.createdAt == fixtureCreatedAt)
        #expect(after.deletedAt == nil)
        #expect(after.displayUnit == .pounds)
    }

    /// A backup row from another device: every preference moved off the bootstrap's choice, so a
    /// restore that wrote nothing is visible in each column rather than in one.
    ///
    /// - Returns: The record.
    private func foreignBackupSettings() -> UserSettings {
        UserSettings(
            id: UUID(),
            createdAt: fixtureCreatedAt,
            updatedAt: fixtureUpdatedAt,
            deletedAt: Date(timeIntervalSince1970: 0),
            userID: UUID(),
            displayUnit: .pounds,
            e1RMFormula: .brzycki,
            theme: .light,
            defaultRoundingIncrement: Weight(grams: 1134),
            defaultRoundingStrategy: .down,
            displayPrecision: DisplayPrecision(milliUnits: 100),
            e1RMLookbackDays: 30,
            keepScreenAwake: false,
            dashboardExerciseIDs: [ExportedIDs.first, ExportedIDs.second]
        )
    }

    @Test("A saved profile cannot claim the default flag", arguments: Subject.all)
    func aSaveCannotClaimTheDefault(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let id = UUID()

        try await repositories.equipment.save(profileRecord(id: id, isDefault: true))

        #expect(try await repositories.equipment.defaultProfile() == nil)
        #expect(
            try await repositories.equipment.profile(id: id, includingDeleted: false)?.isDefault
                == false)
    }

    @Test("makeDefault promotes one profile and clears the previous one", arguments: Subject.all)
    func makeDefaultMovesTheFlag(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let first = UUID()
        let second = UUID()
        try await repositories.equipment.save(profileRecord(id: first, name: "Home gym"))
        try await repositories.equipment.save(profileRecord(id: second, name: "Commercial gym"))

        try await repositories.equipment.makeDefault(profileID: first)
        #expect(try await repositories.equipment.defaultProfile()?.id == first)

        try await repositories.equipment.makeDefault(profileID: second)
        #expect(try await repositories.equipment.defaultProfile()?.id == second)
        #expect(
            try await repositories.equipment.profile(id: first, includingDeleted: false)?.isDefault
                == false)
    }

    /// The finding a second review round produced on the store side, and the reason it is a
    /// conformance claim: assigning the flag to a row that already holds it still counts as a
    /// write, and `updatedAt` is `G-2.4`'s conflict key — so a no-op local write outranks a real
    /// edit made on another device and reverts it silently.
    @Test("makeDefault does not restamp a profile whose flag did not move", arguments: Subject.all)
    func aBystanderProfileIsNotRestamped(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let promoted = UUID()
        let bystander = UUID()
        try await repositories.equipment.save(profileRecord(id: promoted, name: "Home gym"))
        try await repositories.equipment.save(profileRecord(id: bystander, name: "Commercial gym"))
        let before = try #require(
            try await repositories.equipment.profile(id: bystander, includingDeleted: false))

        try await repositories.equipment.makeDefault(profileID: promoted)

        let after = try #require(
            try await repositories.equipment.profile(id: bystander, includingDeleted: false))
        #expect(after.updatedAt == before.updatedAt)

        // Both halves, so the test cannot be satisfied by writing less: the promoted row *is*
        // stamped.
        let winner = try #require(
            try await repositories.equipment.profile(id: promoted, includingDeleted: false))
        #expect(winner.isDefault)
        #expect(winner.updatedAt > before.updatedAt)
    }

    @Test("makeDefault on a deleted or absent profile is refused", arguments: Subject.all)
    func makeDefaultNeedsALiveProfile(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let id = UUID()
        try await repositories.equipment.save(profileRecord(id: id))
        try await repositories.equipment.deleteProfile(id: id)

        await #expect(throws: RepositoryError.recordNotFound(id: id)) {
            try await repositories.equipment.makeDefault(profileID: id)
        }
    }

    @Test("A deleted profile is not the default, whatever flag it carried", arguments: Subject.all)
    func deletingTheDefaultLeavesNoDefault(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let id = UUID()
        try await repositories.equipment.save(profileRecord(id: id))
        try await repositories.equipment.makeDefault(profileID: id)

        try await repositories.equipment.deleteProfile(id: id)

        #expect(try await repositories.equipment.defaultProfile() == nil)
        #expect(
            try await repositories.equipment.profile(id: id, includingDeleted: true)?.isDefault
                == true)
    }

    @Test("A save over a profile that is the default does not clear the flag", arguments: Subject.all)
    func aSaveLeavesTheFlagWhereItWas(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let id = UUID()
        try await repositories.equipment.save(profileRecord(id: id, name: "Home gym"))
        try await repositories.equipment.makeDefault(profileID: id)

        try await repositories.equipment.save(profileRecord(id: id, name: "Garage", isDefault: false))

        #expect(try await repositories.equipment.defaultProfile()?.id == id)
        #expect(try await repositories.equipment.defaultProfile()?.name == "Garage")
    }
}

/// Two fixed identifiers for the dashboard selection, so the restored order is assertable rather
/// than merely non-empty.
private enum ExportedIDs {
    static let first = UUID(uuid: (1, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0))
    static let second = UUID(uuid: (2, 0, 0, 0, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, 0))
}
