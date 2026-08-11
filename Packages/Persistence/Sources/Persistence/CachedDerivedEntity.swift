import Foundation
import SwiftData

/// An entity holding a derived value that was computed rather than logged (`G-1.5`).
///
/// **`computationVersion` versions the *rules a calculator applies*, nothing else.** Bump it when a
/// code change would produce a different value from identical inputs. It does not cover a settings
/// change and it does not cover source-data mutation: `TR-1.6` and `FR-1.6.4` name both of those as
/// their own triggers. So a cached row is usable only when the version matches **and** neither of
/// the other two has fired — a version match alone is not validity, which is why nothing here is
/// called `isValid`.
///
/// **The number lives beside the algorithm, in the domain layer**, one constant per calculator —
/// `PowerliftingCore`'s `PersonalRecordCalculator.computationVersion` is the first. A copy here
/// would be a version nobody bumps when the rules it describes change, and one module-wide version
/// would invalidate every cache for a change to one calculator.
///
/// **Zero means no version was recorded**, and is never a real version. It is what a defaulted
/// column holds when `G-2.5` supplies one rather than the calculator, so treating it as a version
/// would let a row nothing computed read as current.
///
/// **A cached value that reads a setting needs that setting stored as its own column**, never
/// folded into the version. This is why `TR-0.3.9` caches N-rep maxes only: an N-rep max reads
/// logged weights, reps and the two `G-1.8` flags and nothing else, so one scalar is sufficient,
/// while a best e1RM depends on the `E1RMFormulaID` setting and one scalar cannot carry it.
protocol CachedDerivedEntity: StoredEntity {
    /// The version of the calculator's rules that produced the cached value (`G-1.5`).
    var computationVersion: Int { get set }
}

extension CachedDerivedEntity {
    /// Whether the row was produced by `version` of the rules.
    ///
    /// One of the three invalidation triggers, and never sufficient on its own — the caller still
    /// owes the settings and source-mutation checks (`TR-1.6`, `FR-1.6.4`).
    func wasComputed(byRulesVersion version: Int) -> Bool {
        computationVersion == version
    }
}
