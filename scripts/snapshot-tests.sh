#!/usr/bin/env bash
#
# TR-1.12: render every DesignSystem component and compare it against its committed reference.
#
#   scripts/snapshot-tests.sh              # compare against the committed references
#   scripts/snapshot-tests.sh --record     # regenerate every reference, then verify the new set
#
# WHY THIS IS NOT A STEP IN THE `test` JOB. The references are iOS renderings, so the suite needs a
# simulator, and `build-packages.sh --test` runs `swift test` on macOS where the same view resolves
# macOS font metrics. The snapshot target is therefore `#if os(iOS)` throughout: on macOS it
# compiles to nothing and reports no tests. That is a silent pass, which is why this script asserts
# a MINIMUM TEST COUNT rather than trusting the exit status — a `-only-testing:` typo, a renamed
# target or a stray `#if` would otherwise leave a green job enforcing nothing.
#
# WHY THE DEVICE BARELY MATTERS. Every reference is rendered at a fixed width and scale (see
# SnapshotHarness.swift), so the destination contributes only its OS version, which is what resolves
# the fonts. Override it with SNAPSHOT_DESTINATION when the pinned device is missing; a different
# iOS *version* is the one substitution that will fail the comparison.
#
# REGENERATING. `--record` deletes the reference directory and runs the suite twice: the first run
# records what is missing and fails on purpose (a reference nobody has looked at must never make a
# run green), the second verifies the set it just wrote. Deleting first is also what prunes a
# reference whose test no longer exists.

set -euo pipefail

cd "$(dirname "$0")/.."

PACKAGE="Packages/DesignSystem"
SCHEME="DesignSystem-Package"
TEST_TARGET="DesignSystemSnapshotTests"
REFERENCES="$PACKAGE/Tests/$TEST_TARGET/__Snapshots__"
DESTINATION="${SNAPSHOT_DESTINATION:-platform=iOS Simulator,OS=latest,name=iPhone 17 Pro}"

# The suite is 5 suites of tests as of T-1.08. The floor is deliberately below that and deliberately
# not zero: it exists to catch a run that executed *nothing*, not to be updated whenever a test is
# added.
MINIMUM_TESTS=20

RECORD=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --record) RECORD=1; shift ;;
        -h|--help)
            awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
            exit 0 ;;
        *) echo "snapshot-tests.sh: unknown option '$1'" >&2; exit 64 ;;
    esac
done

log=$(mktemp -t snapshot-tests)
trap 'rm -f "$log"' EXIT

run_suite() {
    (
        cd "$PACKAGE"
        xcodebuild test \
            -scheme "$SCHEME" \
            -destination "$DESTINATION" \
            -only-testing:"$TEST_TARGET"
    ) > "$log" 2>&1
}

# swift-testing prints "Test run with N tests in M suites passed|failed". A run that compiled to
# nothing prints no such line at all, which is exactly the case this reads for.
executed_tests() {
    sed -nE 's/.*Test run with ([0-9]+) tests? in .*/\1/p' "$log" | tail -1
}

# The interesting lines are swift-testing's own issue lines, and they are nowhere near the end of a
# 700-line xcodebuild log — a bare `tail` reports only that something failed, which is the one thing
# the exit status already said.
report_failure() {
    echo "--- failures ---" >&2
    grep -E "SNAPSHOT MISMATCH|Expectation failed|error:|✘ Suite|✘ Test run" "$log" | head -40 >&2
    echo "--- xcodebuild output (last 15 lines) ---" >&2
    tail -15 "$log" >&2
}

if (( RECORD )); then
    echo "==> deleting $REFERENCES"
    rm -rf "$REFERENCES"
    echo "==> recording (this run is expected to fail: every reference is missing)"
    if run_suite; then
        echo "snapshot-tests.sh: the recording run PASSED, which it cannot do with no references." >&2
        echo "Either the suite ran nothing, or a missing reference no longer fails a run." >&2
        report_failure
        exit 70
    fi
    echo "==> recorded $(find "$REFERENCES" -name '*.png' | wc -l | tr -d ' ') references; verifying them"
fi

if ! run_suite; then
    echo "snapshot-tests.sh: snapshots do not match. Rendered images and diffs are in" >&2
    echo "  $PACKAGE/.build/snapshot-failures/" >&2
    echo "If the change is intended: scripts/snapshot-tests.sh --record, then review the diff." >&2
    report_failure
    exit 1
fi

count=$(executed_tests)
if [[ -z "$count" ]]; then
    echo "snapshot-tests.sh: the run reported no test count at all — it executed nothing." >&2
    report_failure
    exit 70
fi
if (( count < MINIMUM_TESTS )); then
    echo "snapshot-tests.sh: only $count tests ran, expected at least $MINIMUM_TESTS." >&2
    echo "A snapshot target that compiles to nothing passes; that is what this check is for." >&2
    report_failure
    exit 70
fi

echo "$count snapshot tests passed against $(find "$REFERENCES" -name '*.png' | wc -l | tr -d ' ') references."
