import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-1.4.2`'s form, as the values it resolves to and the values it refuses. What it looks like is
/// the snapshot suite's question; the arithmetic itself is Phase 0's.
@Suite("Equipment profile draft")
struct EquipmentProfileDraftTests {
    /// The locale every case here parses and renders in.
    private static let locale = Locale(identifier: "en_US_POSIX")

    @Test("The collar field is one collar, and the loading is worked out from two of them")
    func collarIsOneCollarNotThePair() throws {
        // TR-0.3.7's most specifically-flagged trap, from the entry end. A 20 kg bar with 2.5 kg
        // collars is a 25 kg bare bar; the pair reading would make it 22.5 kg and every loading in
        // the app would be 2.5 kg light.
        var draft = EquipmentProfileDraft(unit: .kilograms, locale: Self.locale)
        draft.barText = "20"
        draft.collarText = "2.5"

        let profile = try #require(draft.profile(replacing: nil))
        #expect(profile.collarWeight == Weight(grams: 2_500))

        let calculator = try #require(
            PlateCalculator(
                bar: profile.barWeight,
                collar: profile.collarWeight,
                inventory: try profile.inventory()
            ))
        guard case .exact(let bare) = calculator.loading(for: Weight(grams: 25_000)) else {
            Issue.record("a 20 kg bar with 2.5 kg collars did not load to 25 kg")
            return
        }
        #expect(bare.totalWeight == Weight(grams: 25_000))
        #expect(bare.perSide.isEmpty)
        // And the pair reading does not load at all, which is the half that fails if the field is
        // ever re-read as "both collars".
        guard case .nearest = calculator.loading(for: Weight(grams: 22_500)) else {
            Issue.record("22.5 kg loaded, so the collar was read as the pair")
            return
        }
    }

    @Test("A round trip through the editor leaves a stored profile as it was")
    func editingIsLossless() throws {
        let stored = Self.profile(bar: 20_000, collar: 2_500, plates: [25_000, 1_250], pairs: [4, 1])
        let draft = EquipmentProfileDraft(editing: stored, unit: .kilograms, locale: Self.locale)
        let saved = try #require(draft.profile(replacing: stored))

        #expect(saved.id == stored.id)
        #expect(saved.createdAt == stored.createdAt)
        #expect(saved.name == stored.name)
        #expect(saved.barWeight == stored.barWeight)
        #expect(saved.collarWeight == stored.collarWeight)
        #expect(saved.plates == stored.plates)
        #expect(saved.platePairCounts == stored.platePairCounts)
    }

    @Test("A profile entered in pounds is stored in grams, and comes back in pounds")
    func poundsRoundTrip() throws {
        var draft = EquipmentProfileDraft(unit: .pounds, locale: Self.locale)
        draft.barText = "45"
        draft.collarText = "0"
        draft.plates = [PlateDraft(weightText: "45", pairsText: "4")]

        let profile = try #require(draft.profile(replacing: nil))
        #expect(profile.barWeight == Weight(pounds: 45, rounding: .nearest))
        // Anchored to a literal rather than to the same conversion run twice: the claim is that
        // grams are what is stored, not that two calls agree.
        #expect(profile.barWeight.grams == 20_412)

        let reopened = EquipmentProfileDraft(editing: profile, unit: .pounds, locale: Self.locale)
        #expect(reopened.barText == "45")
        #expect(reopened.plates.map(\.weightText) == ["45"])
    }

    @Test("An empty form refuses, and says nothing about it until something is typed")
    func anUntouchedFormComplainsAboutNothing() {
        let draft = EquipmentProfileDraft(unit: .kilograms, locale: Self.locale)
        #expect(draft.isBlank)
        #expect(!draft.isSavable)
        #expect(draft.refusal == .barNotAWeight)
        #expect(draft.profile(replacing: nil) == nil)
    }

    @Test(
        "Every refusal is reported as itself",
        arguments: [
            // The bar comes first, because it is the first field.
            ("", "0", [(String, String)](), EquipmentDraftRefusal.barNotAWeight),
            ("not a bar", "0", [], .barNotAWeight),
            ("-20", "0", [], .barNotAWeight),
            ("20", "", [], .collarNotAWeight),
            ("20", "-1", [], .collarNotAWeight),
            ("20", "0", [("", "2")], .plateNotAWeight),
            // Under one gram: `PlateInventory` refuses it, so the form has to as well.
            ("20", "0", [("0", "2")], .plateNotAWeight),
            ("20", "0", [("20", "")], .pairCountNotACount),
            ("20", "0", [("20", "1.5")], .pairCountNotACount),
            ("20", "0", [("20", "-1")], .pairCountNotACount),
            ("20", "0", [("20", "2"), ("20", "1")], .repeatedDenomination),
        ])
    func refusals(
        bar: String,
        collar: String,
        plates: [(String, String)],
        expected: EquipmentDraftRefusal
    ) {
        var draft = EquipmentProfileDraft(unit: .kilograms, locale: Self.locale)
        draft.barText = bar
        draft.collarText = collar
        draft.plates = plates.map { PlateDraft(weightText: $0.0, pairsText: $0.1) }

        #expect(draft.refusal == expected)
        #expect(!draft.isSavable)
        #expect(draft.profile(replacing: nil) == nil)
    }

    @Test("A gym stocking nothing is a profile, not an unfinished one")
    func noPlatesIsAValue() throws {
        var draft = EquipmentProfileDraft(unit: .kilograms, locale: Self.locale)
        draft.barText = "20"
        draft.collarText = "0"

        #expect(draft.isSavable)
        let profile = try #require(draft.profile(replacing: nil))
        #expect(profile.plates.isEmpty)
        #expect(profile.platePairCounts.isEmpty)
    }

    @Test("Zero pairs of a denomination is a gym that lists a plate it does not have")
    func zeroPairsIsLegal() throws {
        var draft = EquipmentProfileDraft(unit: .kilograms, locale: Self.locale)
        draft.barText = "20"
        draft.collarText = "0"
        draft.plates = [PlateDraft(weightText: "25", pairsText: "0")]

        let profile = try #require(draft.profile(replacing: nil))
        #expect(profile.platePairCounts == [0])
    }

    @Test("The saved plate lists are always the same length, whatever the row said")
    func savingRepairsAMalformedRow() throws {
        // A stored row whose two lists disagree cannot be projected at all, so the editor is the one
        // place it can be repaired. It opens on the shorter list, and saving writes both from that.
        let malformed = Self.profile(bar: 20_000, collar: 0, plates: [25_000, 20_000], pairs: [1])
        #expect(throws: RecordProjectionError.self) { try malformed.inventory() }

        let draft = EquipmentProfileDraft(editing: malformed, unit: .kilograms, locale: Self.locale)
        #expect(draft.plates.count == 1)
        let saved = try #require(draft.profile(replacing: malformed))
        #expect(saved.plates.count == saved.platePairCounts.count)
        _ = try saved.inventory()
    }

    @Test(
        "A field that is only partly a number is refused, not truncated",
        arguments: [
            // Measured against the parser this replaced: `lenient: false` reads "2,5abc" as 2.5 and
            // "2 5" as 2, hands the prefix back, and leaves the save command lit over a collar the
            // user never entered. A whole-string match is what refuses these.
            "2,5abc", "2 5", "1,2,3", "20x", "2,5252\\b\\b",
        ])
    func aPartialNumberIsRefused(text: String) {
        var draft = EquipmentProfileDraft(unit: .kilograms, locale: Locale(identifier: "de_DE"))
        draft.barText = "20"
        draft.collarText = text

        #expect(draft.refusal == .collarNotAWeight)
        #expect(!draft.isSavable)
    }

    @Test("A weight is read in the locale it was typed in")
    func commaDecimalsParse() throws {
        // The trap `LocalizedNumberField` documents: a lenient read would take "2,5" as 2 and store
        // collars half a kilo light, with nothing on screen saying so.
        var draft = EquipmentProfileDraft(unit: .kilograms, locale: Locale(identifier: "de_DE"))
        draft.barText = "20"
        draft.collarText = "2,5"

        #expect(try #require(draft.profile(replacing: nil)).collarWeight == Weight(grams: 2_500))
    }

    @Test("A name is trimmed, and a form left unnamed stores no name at all")
    func namesAreTrimmed() throws {
        var draft = EquipmentProfileDraft(unit: .kilograms, locale: Self.locale)
        draft.barText = "20"
        draft.collarText = "0"
        draft.name = "  Home gym  "
        #expect(try #require(draft.profile(replacing: nil)).name == "Home gym")

        draft.name = "   "
        #expect(try #require(draft.profile(replacing: nil)).name.isEmpty)
    }

    @Test("A new profile never claims the default flag, and an edit never drops it")
    func theDefaultFlagIsNotTheFormsToWrite() throws {
        var draft = EquipmentProfileDraft(unit: .kilograms, locale: Self.locale)
        draft.barText = "20"
        draft.collarText = "0"
        #expect(try #require(draft.profile(replacing: nil)).isDefault == false)

        let active = Self.profile(
            bar: 20_000, collar: 0, plates: [], pairs: [], isDefault: true)
        #expect(try #require(draft.profile(replacing: active)).isDefault)
    }

    @Test("A form with anything in it is not blank, which is what lets it complain")
    func aTouchedFormIsNotBlank() {
        // The direction that matters. `isBlank` gates the only refusal this form shows, so a version
        // answering `true` unconditionally silences every message on the screen — and the true
        // direction alone cannot see that. One field at a time, because each one has to count.
        var draft = EquipmentProfileDraft(unit: .kilograms, locale: Self.locale)
        #expect(draft.isBlank)

        draft.name = "   "
        #expect(draft.isBlank, "whitespace is not something typed")

        draft.name = "Home gym"
        #expect(draft.isBlank == false)

        draft = EquipmentProfileDraft(unit: .kilograms, locale: Self.locale)
        draft.barText = "20"
        #expect(draft.isBlank == false)

        draft = EquipmentProfileDraft(unit: .kilograms, locale: Self.locale)
        draft.collarText = "0"
        #expect(draft.isBlank == false)

        // A row added and not yet filled in is still a form the user has touched.
        draft = EquipmentProfileDraft(unit: .kilograms, locale: Self.locale)
        draft.plates = [PlateDraft()]
        #expect(draft.isBlank == false)
    }

    @Test("A new gym's identity is minted once, not at every save")
    func theNewProfileIdentityIsStable() throws {
        // The save is async and the command outlives it, so this resolves twice on a double tap.
        // An identity minted here would make the second attempt an insert rather than a replace.
        var draft = EquipmentProfileDraft(unit: .kilograms, locale: Self.locale)
        draft.barText = "20"
        draft.collarText = "0"

        let first = try #require(draft.profile(replacing: nil))
        let second = try #require(draft.profile(replacing: nil))
        #expect(first.id == second.id)
        #expect(first.id == draft.newProfileID)

        // And two forms are still two gyms — the identity is the draft's, not the type's.
        var other = EquipmentProfileDraft(unit: .kilograms, locale: Self.locale)
        other.barText = "20"
        other.collarText = "0"
        #expect(try #require(other.profile(replacing: nil)).id != first.id)
    }

    /// A profile record, with only the fields these cases vary.
    private static func profile(
        bar: Int,
        collar: Int,
        plates: [Int],
        pairs: [Int],
        name: String = "Home gym",
        isDefault: Bool = false
    ) -> EquipmentProfile {
        EquipmentProfile(
            id: UUID(),
            createdAt: .distantPast,
            updatedAt: .distantPast,
            deletedAt: nil,
            name: name,
            barWeight: Weight(grams: bar),
            collarWeight: Weight(grams: collar),
            plates: plates.map(Weight.init(grams:)),
            platePairCounts: pairs,
            isDefault: isDefault
        )
    }
}
