// FIXTURE — must trigger `missing_docs` (NFR-0.3, T-0.23).
//
// The type below conforms to `Sendable`, and that is the whole point of it.
//
// `missing_docs` defaults to `excludes_inherited_types: true`, which skips any type carrying a
// conformance clause together with every one of its members. Every type in PowerliftingCore
// conforms to at least `Sendable`, so at the rule's defaults it gates *nothing* in the module it
// was enabled for. Measured 2026-08-07 on SwiftLint 0.65.0: 0 violations across
// Packages/PowerliftingCore/Sources at the defaults, 18 with `excludes_inherited_types: false`.
//
// So a fixture that is a bare undocumented struct would fire in both configurations and prove
// nothing. This one fires only while the boolean is false. Flip it back in .swiftlint.yml and
// verify-lint-rules.sh goes red — which is the regression T-0.14 says to guard, a rule shipping
// with the exact hole it was written to close.
//
// Two violations are expected here, not one: the type and the property.

public struct MissingDocsFixture: Sendable {
    public let grams: Int
}
