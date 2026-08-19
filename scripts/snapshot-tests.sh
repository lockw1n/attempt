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
# WHAT THE RUN COMPARED rather than trusting the exit status — a `-only-testing:` typo, a renamed
# target or a stray `#if` would otherwise leave a green job enforcing nothing.
#
# Two assertions, because one number cannot do it. Every reference the suite matches is announced by
# the harness, and the count of those has to equal the number of committed references: that is what
# notices a suite dropping out of the run while its images stay in the tree. And a minimum test
# count, for the tests that back no reference at all — the harness probes, which are the half of
# this suite that proves the comparison can fail.
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

# 27 tests in 5 suites as of T-1.08: 15 back a reference, 12 probe the harness. The floor sits
# ABOVE the 15 on purpose. Reference parity below already covers every reference-backed test
# exactly, so the only thing left for a count to notice is the probe suites going missing — and a
# floor under 15 could not notice that, because the reference tests alone would clear it.
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

# One line per reference the harness matched, printed by assertSnapshot. Deduplicated because
# xcodebuild echoes the test process's stdout in more than one place.
compared_references() {
    sed -nE 's/.*SNAPSHOT COMPARED ([^[:space:]]+).*/\1/p' "$log" | sort -u | wc -l | tr -d ' '
}

committed_references() {
    find "$REFERENCES" -name '*.png' | wc -l | tr -d ' '
}

# The interesting lines are swift-testing's own issue lines, and they are nowhere near the end of a
# 700-line xcodebuild log — a bare `tail` reports only that something failed, which is the one thing
# the exit status already said.
#
# `|| true` IS LOAD-BEARING. Under `set -euo pipefail` a grep that matches nothing returns 1 and
# takes the whole script down with it — before the caller reaches its own `exit 70`. The callers
# that most need this are exactly the ones with nothing to match: a run whose tests all passed and
# whose *gate* is what failed. Measured: without it those paths exit 1, silently collapsing the
# distinction between "snapshots differ" and "this gate is not enforcing anything".
#
# `cut` bounds a line rather than a count. `head -40` counts lines, and one swift-testing line can
# carry an entire operand.
report_failure() {
    echo "--- failures ---" >&2
    grep -E "SNAPSHOT MISMATCH|Expectation failed|error:|✘ Suite|✘ Test run" "$log" \
        | cut -c1-400 | head -40 >&2 || true
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
    echo "==> recorded $(committed_references) references; verifying them"
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

references=$(committed_references)
compared=$(compared_references)
if [[ "$compared" != "$references" ]]; then
    echo "snapshot-tests.sh: the run compared $compared references, but the directory holds $references." >&2
    echo "  $REFERENCES" >&2
    echo "A suite that stops being run leaves its references behind, and a reference whose test was" >&2
    echo "deleted stays in the tree; both are green under a test count and neither is under this." >&2
    echo "If a reference is genuinely obsolete: scripts/snapshot-tests.sh --record." >&2
    report_failure
    exit 70
fi

echo "$count snapshot tests passed, comparing all $references references."
