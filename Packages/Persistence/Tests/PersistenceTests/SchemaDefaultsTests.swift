import Foundation
import PowerliftingCore
import Testing

@testable import Persistence

// Every default is pinned to a literal rather than to the expression that produces it, for the
// reason T-0.11's raw-value tests give: comparing `SchemaDefaults.movement` with
// `Movement.other.rawValue` only proves the constant agrees with itself.
//
// What these cannot check is that SwiftData records these values as the store's *column* defaults.
// Observing that needs a two-version store, which is T-0.34's apparatus and where the probe belongs.
@Suite("Schema defaults")
struct SchemaDefaultsTests {
    // G-2.5 forces a default onto every non-optional join key. A stable sentinel is what lets one
    // predicate find every unwritten reference; UUID() would mint a distinct dangling one per row.
    @Test("An unwritten join key is the all-zero UUID")
    func unlinkedIDIsTheZeroUUID() {
        #expect(SchemaDefaults.unlinkedID.uuidString == "00000000-0000-0000-0000-000000000000")
    }

    @Test("The vocabulary defaults are the deliberate cases, by spelling")
    func vocabularyDefaults() {
        #expect(SchemaDefaults.movement == "other")
        #expect(SchemaDefaults.equipment == "other")
        #expect(SchemaDefaults.laterality == "bilateral")
        #expect(SchemaDefaults.barType == "other")
    }

    // A spelling that no case answers to would leave the repository's mapping with nothing to fall
    // back to, which is the whole point of choosing these four.
    @Test("Each vocabulary default names a real case")
    func vocabularyDefaultsResolve() {
        #expect(Movement(rawValue: SchemaDefaults.movement) == .other)
        #expect(Equipment(rawValue: SchemaDefaults.equipment) == .other)
        #expect(Laterality(rawValue: SchemaDefaults.laterality) == .bilateral)
        #expect(BarType(rawValue: SchemaDefaults.barType) == .other)
    }

    // Zero here would silently flatten every tonnage figure to nothing.
    @Test("An exercise loads one implement unless it says otherwise")
    func implementCountDefault() {
        #expect(SchemaDefaults.implementCount == 1)
    }

    // TR-0.2.8's tie-break resolves to the earlier set, so a distant-past sentinel here would win
    // every tie a session with no written date took part in. Minted per read, like `id` and unlike
    // `unlinkedID` — a session that arrives without a date is not the same session as any other.
    @Test("An unwritten session date is the present, not a sentinel")
    func sessionDateIsNotASentinel() {
        #expect(SchemaDefaults.sessionDate.timeIntervalSinceNow > -1)
        #expect(SchemaDefaults.sessionDate > Date(timeIntervalSince1970: 1_700_000_000))
    }

    // G-1.8: a set nobody classified must not read as a completed working set, because that is the
    // one combination analytics counts — and a personal record, once badged, outlives its row.
    @Test("An unclassified set is neither a warmup nor completed")
    func setFlagDefaults() {
        #expect(SchemaDefaults.isWarmup == false)
        #expect(SchemaDefaults.isCompleted == false)
    }

    // The three storage vocabularies, by spelling. `manual` twice, for two unrelated reasons: a
    // reading of unknown provenance must not suppress a typed one under FR-1.8.2's de-duplication,
    // and a training-max source of unknown kind must refuse to resolve rather than quietly hand back
    // 90% of the user's e1RM.
    @Test("The supporting vocabulary defaults are the deliberate cases, by spelling")
    func supportingVocabularyDefaults() {
        #expect(SchemaDefaults.bodyweightSource == "manual")
        #expect(SchemaDefaults.trainingMaxSource == "manual")
        #expect(SchemaDefaults.roundingStrategy == "nearest")
        #expect(SchemaDefaults.displayUnit == "kilograms")
        #expect(SchemaDefaults.e1RMFormula == "epley")
        #expect(SchemaDefaults.theme == "system")
    }

    @Test("Each supporting default names a real case")
    func supportingVocabularyDefaultsResolve() {
        #expect(BodyweightSource(rawValue: SchemaDefaults.bodyweightSource) == .manual)
        #expect(TrainingMaxSourceKind(rawValue: SchemaDefaults.trainingMaxSource) == .manual)
        #expect(RoundingStrategy(rawValue: SchemaDefaults.roundingStrategy) == .nearest)
        #expect(MassUnit(rawValue: SchemaDefaults.displayUnit) == .kilograms)
        #expect(E1RMFormulaID(rawValue: SchemaDefaults.e1RMFormula) == .epley)
        #expect(ThemePreference(rawValue: SchemaDefaults.theme) == .system)
    }

    // One constant, in the domain layer, doing both jobs — the formula a lifter gets before opening
    // settings and the fallback for a name this app cannot read. A second one here would drift.
    @Test("The formula default is the domain layer's, not a copy of it")
    func e1RMFormulaDefaultIsNotASecondConstant() {
        #expect(SchemaDefaults.e1RMFormula == E1RMFormulaID.defaultFormula.rawValue)
    }

    // Zero is not available here: RoundingRule refuses an increment below one gram, so a column
    // defaulting to zero could not be mapped to a rule at all.
    @Test("The default rounding increment is loadable, and zero would not be")
    func roundingIncrementDefaultIsLoadable() {
        #expect(SchemaDefaults.roundingIncrementGrams == 2_500)
        #expect(
            RoundingRule(
                increment: Weight(grams: SchemaDefaults.roundingIncrementGrams),
                strategy: .nearest
            ) != nil
        )
        #expect(RoundingRule(increment: Weight(grams: 0), strategy: .nearest) == nil)
    }

    @Test("The default training-max percentage is the domain layer's 90%, as a ratio")
    func trainingMaxPercentageDefault() {
        #expect(SchemaDefaults.trainingMaxPercentage == 0.9)
    }

    // Two date defaults pointing at *now* and two pointing at the distant past, and the direction is
    // per column rather than per module: `sessionDate` and `bodyweightDate` must not anchor the far
    // past, while `effectiveFrom` must lose every lookup against a real configuration and
    // `achievedAt` must never read as a record set just now.
    @Test("The four date defaults point in the two directions their lookups need")
    func dateDefaultDirections() {
        #expect(SchemaDefaults.bodyweightDate.timeIntervalSinceNow > -1)
        #expect(SchemaDefaults.bodyweightDate > Date(timeIntervalSince1970: 1_700_000_000))
        #expect(SchemaDefaults.effectiveFrom == Date.distantPast)
        #expect(SchemaDefaults.achievedAt == Date.distantPast)
        #expect(SchemaDefaults.effectiveFrom < SchemaDefaults.sessionDate)
    }
}
