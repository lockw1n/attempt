// FIXTURE — this file emits a compiler warning on purpose. Do not "fix" it.
//
// scripts/verify-warnings-gate.sh compiles this package twice: once plain, expecting success,
// and once with the flags from swift-strict-flags.sh, expecting failure. If someone tidies the
// warning away, both builds pass, the script reports that the gate is unproven, and CI fails —
// which is the intended outcome, because at that point the fixture is no longer testing anything.

public enum WarningGateFixture {
    public static func probe() -> Int {
        // warning: initialization of immutable value 'unused' was never used
        let unused = 1
        return 0
    }
}
