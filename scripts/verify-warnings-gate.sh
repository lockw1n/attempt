#!/usr/bin/env bash
#
# G-6.4: prove the warnings-as-errors gate actually fails a build.
#
#   scripts/verify-warnings-gate.sh
#
# WHY. T-0.03 moved warnings-as-errors out of the package manifests and into command-line flags
# (see swift-strict-flags.sh). A flag is easier to lose than a manifest setting — a refactor of
# build-packages.sh, a CI step edited to call `swift build` directly, or a typo in the flag name
# all leave every build passing and nothing enforcing anything. That failure is invisible because
# it looks exactly like success.
#
# So the gate gets a test, the same way T-0.08's Linux tripwire and verify-lint-rules.sh do.
# Both directions are checked, and both matter:
#
#   WITHOUT the flags  the fixture must BUILD    — proving the fixture's warning is only a warning,
#                                                  so a failure below is attributable to the flags
#                                                  and not to broken fixture code.
#   WITH the flags     the fixture must FAIL     — proving the flags still promote it to an error.
#
# Checking only the second direction would pass even if the fixture had a syntax error, which
# would be a gate that tests nothing while looking rigorous.

set -euo pipefail

cd "$(dirname "$0")/.."
source "$(dirname "$0")/swift-strict-flags.sh"

FIXTURE="scripts/warning-gate-fixture"
[[ -f "$FIXTURE/Package.swift" ]] || {
    echo "error: fixture package missing at $FIXTURE" >&2
    exit 66
}

# A scratch build directory, so this never reuses or pollutes a real .build tree.
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

failures=0

echo "1/2  without ${SWIFT_STRICT_FLAGS[*]} — the fixture must build"
if swift build --package-path "$FIXTURE" --scratch-path "$SCRATCH/plain" >/dev/null 2>&1; then
    echo "     ok    builds clean, so its warning is only a warning"
else
    echo "     FAIL  the fixture does not build even without the flags." >&2
    echo "           Its code is broken, so the check below would prove nothing. Fix the fixture." >&2
    failures=$((failures + 1))
fi

echo "2/2  with    ${SWIFT_STRICT_FLAGS[*]} — the fixture must fail"
if swift build --package-path "$FIXTURE" --scratch-path "$SCRATCH/strict" \
        "${SWIFT_STRICT_FLAGS[@]}" >/dev/null 2>&1; then
    echo "     FAIL  the build SUCCEEDED. Warnings are not being treated as errors." >&2
    echo "           G-6.4 is unenforced right now — check swift-strict-flags.sh and that every" >&2
    echo "           build path actually passes \${SWIFT_STRICT_FLAGS[@]}." >&2
    failures=$((failures + 1))
else
    echo "     ok    fails to build, so the flags still have teeth"
fi

echo
if (( failures > 0 )); then
    echo "$failures/2 checks failed — the warnings gate is not proven." >&2
    exit 1
fi

echo "warnings-as-errors gate verified in both directions."
