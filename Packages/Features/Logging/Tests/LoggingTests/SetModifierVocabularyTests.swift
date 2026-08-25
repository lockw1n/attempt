import Foundation
import PowerliftingCore
import Testing

@testable import Logging

/// `FR-1.2.8`'s configurable list: what it offers, what it refuses, and what it deliberately does
/// **not** touch.
///
/// **The contract worth a suite is the one that is invisible from the type's signature**: the
/// vocabulary and a logged set are separate, so renaming or removing a term leaves every set that
/// carries it exactly as it was (`G-1.6`). Getting that wrong is not a compile error anywhere.
@Suite("The configurable modifier list")
struct SetModifierVocabularyTests {
    /// A list nothing else can see, so one test's terms stay out of the next one's.
    ///
    /// - Parameter stored: What the suite should start out holding, if anything.
    /// - Returns: The list, and the suite it is kept in.
    private static func vocabulary(stored: [String] = []) -> (SetModifierVocabulary, UserDefaults) {
        let name = "modifiers.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            Issue.record("no throwaway defaults suite")
            return (SetModifierVocabulary(defaults: .standard), .standard)
        }
        if !stored.isEmpty { defaults.set(stored, forKey: SetModifierVocabulary.key) }
        return (SetModifierVocabulary(defaults: defaults), defaults)
    }

    @Test("The nine built-in terms are offered, and are the list a fresh install starts from")
    func theBuiltInTermsAreOffered() {
        let (vocabulary, _) = Self.vocabulary()

        #expect(vocabulary.custom.isEmpty)
        #expect(vocabulary.terms.count == 9)
        #expect(vocabulary.terms == SetModifierTerm.allCases.map(SetModifier.init))
        // Anchored to a literal, so a `terms` that answered `[]` could not satisfy this by matching
        // an equally empty right-hand side.
        #expect(vocabulary.terms.contains(SetModifier(.belt)))
        #expect(vocabulary.terms.contains(SetModifier(.touchAndGo)))
    }

    @Test("A term the user adds joins the list, after the built-ins")
    func addingATermOffersIt() {
        let (vocabulary, _) = Self.vocabulary()

        let added = vocabulary.add("chains")

        #expect(added == SetModifier(rawValue: "chains"))
        #expect(vocabulary.custom == ["chains"])
        #expect(vocabulary.terms.last == SetModifier(rawValue: "chains"))
        #expect(vocabulary.terms.count == 10)
    }

    @Test("What is typed is trimmed, and a blank or duplicated term is refused")
    func addingRefusesWhatItCannotOffer() {
        let (vocabulary, _) = Self.vocabulary()

        #expect(vocabulary.add("  chains  ") == SetModifier(rawValue: "chains"))
        // Trimmed, so the second one is the same term.
        #expect(vocabulary.add("chains") == nil)
        #expect(vocabulary.add("") == nil)
        #expect(vocabulary.add("   ") == nil)
        // A built-in spelling is a duplicate too — otherwise the picker would draw two "Belt" rows,
        // one of which the app recognises.
        #expect(vocabulary.add("belt") == nil)
        // Case-insensitively, and against the drawn name: the software keyboard capitalises the
        // first word, so `belt` typed into the field arrives as `Belt` — a term the app would
        // neither recognise nor refuse, drawn as a second row nobody could tell from the first.
        #expect(vocabulary.add("Belt") == nil)
        #expect(vocabulary.add("CHAINS") == nil)
        #expect(vocabulary.add("Touch and go") == nil)
        #expect(vocabulary.custom == ["chains"])
    }

    @Test("Only the user's own terms can be renamed or removed")
    func theBuiltInTermsAreNotEditable() {
        let (vocabulary, _) = Self.vocabulary(stored: ["chains"])

        #expect(vocabulary.isEditable(SetModifier(rawValue: "chains")))
        #expect(!vocabulary.isEditable(SetModifier(.belt)))
        #expect(!vocabulary.rename(SetModifier(.belt), to: "girdle"))
        #expect(!vocabulary.remove(SetModifier(.belt)))
        #expect(vocabulary.terms.contains(SetModifier(.belt)))
        #expect(vocabulary.terms.count == 10)
    }

    @Test("A rename keeps the term's place, and is refused where an add would be")
    func renamingKeepsThePosition() {
        let (vocabulary, _) = Self.vocabulary(stored: ["chains", "bands"])

        #expect(vocabulary.rename(SetModifier(rawValue: "chains"), to: " chain  "))
        #expect(vocabulary.custom == ["chain", "bands"])
        #expect(!vocabulary.rename(SetModifier(rawValue: "chain"), to: ""))
        #expect(!vocabulary.rename(SetModifier(rawValue: "chain"), to: "bands"))
        #expect(!vocabulary.rename(SetModifier(rawValue: "chain"), to: "belt"))
        // Renaming a term to what it already is writes nothing rather than reporting a change.
        #expect(!vocabulary.rename(SetModifier(rawValue: "chain"), to: "chain"))
        #expect(vocabulary.custom == ["chain", "bands"])
        // But a term is not its own duplicate: correcting its capitalisation goes through, which is
        // the likeliest reason to rename one at all.
        #expect(vocabulary.rename(SetModifier(rawValue: "chain"), to: "Chain"))
        #expect(vocabulary.custom == ["Chain", "bands"])
    }

    @Test("Removing a term stops it being offered, and removing one twice is not an error")
    func removingATermStopsOfferingIt() {
        let (vocabulary, _) = Self.vocabulary(stored: ["chains", "bands"])

        #expect(vocabulary.remove(SetModifier(rawValue: "chains")))
        #expect(vocabulary.custom == ["bands"])
        #expect(!vocabulary.remove(SetModifier(rawValue: "chains")))
        #expect(vocabulary.custom == ["bands"])
    }

    @Test("A term the user added survives a relaunch")
    func theListIsStored() {
        let (vocabulary, defaults) = Self.vocabulary()

        vocabulary.add("chains")
        vocabulary.add("bands")
        vocabulary.rename(SetModifier(rawValue: "bands"), to: "band pull")
        // A second object over the same suite is what a relaunch is: nothing of the first survives
        // but what it wrote.
        let reopened = SetModifierVocabulary(defaults: defaults)

        #expect(reopened.custom == ["chains", "band pull"])
        #expect(reopened.terms.contains(SetModifier(rawValue: "band pull")))
    }

    @Test("A spelling the list does not offer is still drawn where a set carries it")
    func anUnlistedSpellingIsStillOffered() {
        let (vocabulary, _) = Self.vocabulary(stored: ["chains"])
        let unlisted = SetModifier(rawValue: "reverse band")

        let rows = vocabulary.offered(with: [SetModifier(.belt), unlisted, unlisted])

        // The whole of `OpenVocabulary`'s preservation reaching a screen: a picker offered only the
        // terms it knows would draw this set as though the modifier were not there, and the next
        // confirm would drop it.
        #expect(rows.last == unlisted)
        #expect(rows.count == vocabulary.terms.count + 1)
        // Offered ones keep their place and are not repeated by being applied.
        #expect(rows.prefix(vocabulary.terms.count) == vocabulary.terms[...])
    }

    @Test("Tapping a row applies the term, and tapping it again takes it off")
    func togglingATermIsItsOwnInverse() {
        let belt = SetModifier(.belt)
        let chains = SetModifier(rawValue: "chains")

        let one = SetModifierPicker.toggling(belt, in: [])
        let two = SetModifierPicker.toggling(chains, in: one)
        let back = SetModifierPicker.toggling(belt, in: two)

        #expect(one == [belt])
        #expect(two == [belt, chains])
        #expect(back == [chains])
        #expect(SetModifierPicker.toggling(chains, in: back).isEmpty)
    }

    @Test("A built-in term draws its own copy and an invented one draws its spelling")
    func aTermDrawsTheNameItHas() {
        #expect(SetModifier(.belt).displayName == "Belt")
        #expect(SetModifier(.touchAndGo).displayName == "Touch and go")
        // No localised name exists for a word the user invented, and drawing nothing would be
        // indistinguishable from the modifier not being there.
        #expect(SetModifier(rawValue: "chains").displayName == "chains")
        #expect(SetModifier(rawValue: "").displayName.isEmpty)
    }
}
