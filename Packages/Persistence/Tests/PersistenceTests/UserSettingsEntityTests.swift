import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData
import Testing

@testable import Persistence

@Suite("UserSettingsEntity")
struct UserSettingsEntityTests {
    @Test("Every preference survives a save and a re-read, in its own column")
    func roundTrips() throws {
        let context = try makeSupportingContext()
        let userID = try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00CF4FC964FF"))
        context.insert(
            makeSettings(
                userID: userID,
                displayUnit: .pounds,
                e1RMFormula: .oConner,
                theme: .light,
                defaultRoundingIncrementGrams: 1_250,
                defaultRoundingStrategy: .up
            )
        )
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<UserSettingsEntity>.notDeleted()).first
        )

        #expect(stored.userID == userID)
        #expect(stored.displayUnitRawValue == "pounds")
        // Note the spelling: E1RMFormulaID deliberately stores "oconner", not Swift's "oConner".
        #expect(stored.e1RMFormulaRawValue == "oconner")
        #expect(stored.themeRawValue == "light")
        #expect(stored.defaultRoundingIncrementGrams == 1_250)
        #expect(stored.defaultRoundingStrategyRawValue == "up")
    }

    // TR-1.10's stability half, which is the half this layer can hold: the id a settings row is
    // created with is the id it reads back, and the schema never mints one of its own. `private(set)`
    // with no writer is what makes "stable thereafter" a compiler fact rather than a rule — this
    // pins the other side of it, that `init` does not quietly substitute a fresh UUID.
    @Test("The anonymous user id is the one it was created with, and the schema mints none")
    func anonymousUserIDIsNeverMintedHere() throws {
        let context = try makeSupportingContext()
        let userID = try #require(UUID(uuidString: "0DE0B6B3-A764-0000-0000-00000000002A"))
        let settings = makeSettings(userID: userID)
        context.insert(settings)
        try context.saveStamped()

        // A second write of an unrelated preference must not disturb it either.
        settings.themeRawValue = ThemePreference.light.rawValue
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<UserSettingsEntity>.notDeleted()).first
        )

        #expect(stored.userID == userID)
        #expect(stored.userID != SchemaDefaults.unlinkedID)
        #expect(stored.themeRawValue == "light")
    }

    // The other half of TR-1.10's "generated once" is not the schema's and cannot be: nothing stops
    // two settings rows existing, each with its own anonymous id, because G-2.5 forbids unique
    // constraints and no store enforces a cross-row predicate. So the first-launch bootstrap has to
    // find-or-create rather than create (TR-0.4.1/TR-0.4.3), and this is the evidence that says so.
    @Test("The store accepts two settings rows with two different user ids")
    func onceIsARepositoryInvariant() throws {
        let context = try makeSupportingContext()
        let first = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let second = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        context.insert(makeSettings(userID: first))
        context.insert(makeSettings(userID: second))
        try context.saveStamped()

        let stored = try context.fetch(FetchDescriptor<UserSettingsEntity>.notDeleted())

        #expect(Set(stored.map(\.userID)) == [first, second])
        #expect(stored.count == 2)
    }

    // The obligation E1RMFormulaID's throw places on this layer, in the form the raw-String rule
    // gives it: a formula name from a newer version is a string this app cannot map, and it must
    // cost that one preference rather than the settings record. `defaultFormula` is what the mapping
    // falls back to — one constant, in the domain layer, doing both jobs.
    @Test("An unreadable formula name costs no other preference")
    func unreadableFormulaLeavesTheRestIntact() throws {
        let context = try makeSupportingContext()
        let userID = try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000AA"))
        let settings = makeSettings(userID: userID, displayUnit: .pounds, theme: .dark)
        settings.e1RMFormulaRawValue = "mayhew"
        context.insert(settings)
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<UserSettingsEntity>.notDeleted()).first
        )

        #expect(stored.e1RMFormulaRawValue == "mayhew")
        #expect(E1RMFormulaID(rawValue: stored.e1RMFormulaRawValue) == nil)
        #expect(E1RMFormulaID.defaultFormula == .epley)
        #expect(stored.userID == userID)
        #expect(stored.displayUnitRawValue == "pounds")
        #expect(stored.themeRawValue == "dark")
        #expect(stored.defaultRoundingIncrementGrams == 5_000)
    }
}

/// The three columns the preferences screen added (`G-3.3`, `FR-1.7.1`, `NFR-1.9`).
@Suite("Settings preferences added after the first screen")
struct UserSettingsPreferenceColumnTests {
    @Test("All three survive a store and a read")
    func columnsRoundTrip() throws {
        let context = try makeSupportingContext()
        context.insert(
            makeSettings(
                userID: UUID(),
                displayPrecisionMilliUnits: 250,
                e1RMLookbackDays: 45,
                keepScreenAwake: false))
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<UserSettingsEntity>.notDeleted()).first)

        #expect(stored.record.displayPrecision == .quarter)
        #expect(stored.record.e1RMLookbackDays == 45)
        #expect(stored.record.keepScreenAwake == false)
    }

    /// `nil` is "never chosen", which the record turns into the unit's own step rather than into a
    /// number the user was never shown — 0.5 kg but 1 lb.
    @Test("An unchosen step is absent rather than zero, and resolves against the unit")
    func absentStepFollowsTheUnit() throws {
        let context = try makeSupportingContext()
        context.insert(
            makeSettings(userID: UUID(), displayUnit: .pounds, displayPrecisionMilliUnits: nil))
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<UserSettingsEntity>.notDeleted()).first)

        #expect(stored.record.displayPrecision == nil)
        #expect(stored.record.weightDisplay.precision == .whole)
    }

    /// A step below one milli-unit maps to no `DisplayPrecision`, and the mapping degrades to the
    /// absent case rather than handing a zero step to something that divides by it.
    @Test("A stored step this app cannot map costs that preference and nothing else")
    func anUnmappableStepDegrades() throws {
        let context = try makeSupportingContext()
        context.insert(
            makeSettings(userID: UUID(), theme: .light, displayPrecisionMilliUnits: 0))
        try context.saveStamped()

        let stored = try #require(
            try context.fetch(FetchDescriptor<UserSettingsEntity>.notDeleted()).first)

        #expect(stored.record.displayPrecision == nil)
        #expect(stored.record.theme == .light)
    }

    /// "Automatic" is a choice the user can come back to, so the column has to *clear*. An update
    /// that only ever wrote a step the user had chosen would pin the old one across every later
    /// relaunch, and this is the one optional column this entity writes through `update(from:)`.
    @Test("Clearing the step clears the column rather than pinning the last one")
    func aClearedStepIsWrittenBack() throws {
        let context = try makeSupportingContext()
        let row = makeSettings(userID: UUID(), displayPrecisionMilliUnits: 250)
        context.insert(row)
        try context.saveStamped()
        var edited = row.record
        edited.displayPrecision = nil

        row.update(from: edited)
        try context.saveStamped()

        #expect(row.displayPrecisionMilliUnits == nil)
        #expect(row.record.displayPrecision == nil)
        // The unit's own step is what stands once the choice is gone — pounds here, so a whole one.
        #expect(row.record.weightDisplay.precision == .whole)
    }

    /// A write that carries the row's preferences must carry every one of them: the columns are
    /// added to the record, and a store keeping its own list drops the newest silently.
    @Test("A preference-only write carries the columns added last")
    func aPreferenceWriteCarriesEveryColumn() throws {
        let context = try makeSupportingContext()
        let row = makeSettings(userID: UUID())
        context.insert(row)
        try context.saveStamped()
        var edited = row.record
        edited.displayPrecision = .tenth
        edited.e1RMLookbackDays = 180
        edited.keepScreenAwake = true

        row.update(from: edited)
        try context.saveStamped()

        #expect(row.record.displayPrecision == .tenth)
        #expect(row.record.e1RMLookbackDays == 180)
        #expect(row.record.keepScreenAwake)
    }
}
