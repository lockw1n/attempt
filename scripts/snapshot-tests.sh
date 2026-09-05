#!/usr/bin/env bash
#
# TR-1.12: render every snapshot suite and compare it against its committed references.
#
#   scripts/snapshot-tests.sh              # compare against the committed references
#   scripts/snapshot-tests.sh --record     # regenerate every reference, then verify the new set
#
# ONE SCRIPT, SEVERAL SUITES. The harness is one library (DesignSystem's SnapshotTesting target) and
# every package that renders anything has its own test target and its own __Snapshots__ beside it —
# the component set here, a screen there. They are listed in SUITES below, and a package added to
# that list is a package this gate covers; a package NOT added is one whose references nothing
# compares, which is the failure this file's assertions are shaped around. Each suite is a separate
# `xcodebuild` invocation because each is a separate SwiftPM package with its own scheme.
#
# WHY THIS IS NOT A STEP IN THE `test` JOB. The references are iOS renderings, so the suites need a
# simulator, and `build-packages.sh --test` runs `swift test` on macOS where the same view resolves
# macOS font metrics. Every snapshot target is therefore `#if os(iOS)` throughout: on macOS it
# compiles to nothing and reports no tests. That is a silent pass, which is why this script asserts
# WHAT EACH RUN COMPARED rather than trusting the exit status — a `-only-testing:` typo, a renamed
# target or a stray `#if` would otherwise leave a green job enforcing nothing.
#
# Two assertions per suite, because one number cannot do it. Every reference the harness matches is
# announced, and the count of those has to equal the number of references committed for that suite:
# that is what notices a suite dropping out of the run while its images stay in the tree. And a
# minimum test count, for the tests that back no reference at all — the harness probes, which are
# the half of this gate that proves the comparison can fail.
#
# WHICH SIMULATOR, AND WHY THE VERSION IS THE HALF THAT MATTERS. Every reference is rendered at a
# fixed width and scale (see SnapshotHarness.swift), so the destination contributes only its OS
# version, which is what resolves the fonts. So the device is RESOLVED and the version is PINNED:
# SNAPSHOT_IOS names the version the committed references were rendered on, and the first available
# iPhone on it is chosen by id.
#
# Measured, not assumed: the full set of 500 references compares clean on iPhone 17 Pro and on
# iPhone 17 — a different size and a different device family, same iOS 26.5. That is the claim this
# resolution rests on, so it is the one worth having run.
#
# A device name was pinned here until it cost a CI run. `name:iPhone 17 Pro` exists on a developer's
# Mac and did not exist on the runner, so xcodebuild refused the destination, nothing was rendered,
# and this script reported "does not match" — naming the one cause (changed pixels) that was not the
# cause. Nothing about a reference depends on which iPhone drew it, so nothing should have to.
#
# The version is pinned rather than resolved for the opposite reason: it DOES change the rendering,
# so a runner image that gained a newer iOS would silently start producing pixel diffs nobody could
# explain. Bump SNAPSHOT_IOS in the same change that re-records — that is the only moment the
# references stop being renderings of the old one. A machine with no simulator on that version is
# told so, rather than being quietly compared against the wrong fonts.
#
# SNAPSHOT_DESTINATION still overrides the whole thing, for a machine this resolution cannot serve.
#
# REGENERATING. `--record` deletes every reference directory and runs each suite twice: the first
# run records what is missing and fails on purpose (a reference nobody has looked at must never make
# a run green), the second verifies the set it just wrote. Deleting first is also what prunes a
# reference whose test no longer exists.

set -euo pipefail

cd "$(dirname "$0")/.."

# package | scheme | test target | minimum tests
#
# The minimum is per suite, and it exists for a suite's NON-reference tests: reference parity below
# already covers the reference-backed ones exactly, so a floor set at the reference count would
# notice nothing the parity check does not. Set it above that count where such tests exist, and at
# the suite's own count where they do not — the latter is a floor that adds nothing, which is the
# honest setting rather than a number chosen to look like the former.
#   DesignSystem:    29 tests, 17 reference-backed, 12 harness probes  -> 22, above the 17.
#   ExerciseLibrary: 35 tests, all of them reference-backed, no probes -> 35, its own count.
#   Logging:         76 tests, 73 reference-backed, a width probe and two layout budgets
#                                                                    -> 76, its own count.
#   History:         20 tests, all of them reference-backed, no probes -> 20, its own count.
#   Dashboard:       18 tests, all of them reference-backed, no probes -> 18, its own count.
#   Settings:        45 tests, all of them reference-backed, no probes -> 45, its own count.
#   Routines:        12 tests, all of them reference-backed, no probes -> 12, its own count.
# A screen suite added later is the ExerciseLibrary case unless it brings probes of its own, and a
# screen added to an existing package raises that package's floor rather than adding a row.
#
# THE FLOOR DRIFTS SILENTLY AND NOTHING BUT THIS COMMENT NOTICES. A suite that gains a test and
# not its floor still passes — the parity check counts references, which move together, and the
# floor is what covers the tests no reference backs. Three of these were stale when T-16.06's
# review counted them (ExerciseLibrary 29 against 34, Logging 59 against 63, Dashboard 10 against
# 15), each drifting one task at a time. `git grep -c '@Test' -- <suite>` is the count to set it
# from, and a task that adds a snapshot test owes this list the same edit it owes __Snapshots__.
SUITES=(
    "Packages/DesignSystem|DesignSystem-Package|DesignSystemSnapshotTests|22"
    "Packages/Features/ExerciseLibrary|ExerciseLibrary|ExerciseLibrarySnapshotTests|35"
    "Packages/Features/Logging|Logging|LoggingSnapshotTests|76"
    "Packages/Features/History|History|HistorySnapshotTests|20"
    "Packages/Features/Dashboard|Dashboard|DashboardSnapshotTests|18"
    "Packages/Features/Settings|Settings|SettingsSnapshotTests|45"
    "Packages/Features/Routines|Routines|RoutinesSnapshotTests|12"
)

# The iOS version the committed references were rendered on. See the header: bump it only when
# re-recording, in the same change.
SNAPSHOT_IOS="${SNAPSHOT_IOS:-26.5}"

# The first available iPhone simulator on SNAPSHOT_IOS, as a destination naming its id.
#
# By id and not by name, because a name is what broke: two runners stock different iPhones and every
# one of them draws these references identically. The iPad section is skipped — the harness renders
# at a fixed width, but a destination has to be something this app actually runs on.
resolved_destination() {
    local version_pattern id
    version_pattern="${SNAPSHOT_IOS//./\\.}"
    id=$(
        xcrun simctl list devices available \
            | sed -n "/^-- iOS ${version_pattern} --\$/,/^-- /p" \
            | sed -nE 's/^ *iPhone[^(]*\(([0-9A-Fa-f-]{36})\).*/\1/p' \
            | head -1
    )
    if [[ -z "$id" ]]; then
        echo "snapshot-tests.sh: no iPhone simulator on iOS ${SNAPSHOT_IOS}, which is the version" >&2
        echo "every committed reference was rendered on. A different version resolves different" >&2
        echo "fonts, so comparing against one would fail on pixels and say nothing about why." >&2
        echo "Install that runtime, or set SNAPSHOT_DESTINATION to accept the substitution." >&2
        echo "--- iPhone simulators this machine has ---" >&2
        xcrun simctl list devices available | grep -E '^-- iOS |iPhone' >&2 || true
        exit 70
    fi
    echo "platform=iOS Simulator,id=$id"
}

DESTINATION="${SNAPSHOT_DESTINATION:-$(resolved_destination)}"
echo "==> rendering against $DESTINATION (iOS $SNAPSHOT_IOS)"

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

references_dir() { echo "$1/Tests/$2/__Snapshots__"; }

run_suite() {
    local package="$1" scheme="$2" target="$3"
    (
        cd "$package"
        xcodebuild test \
            -scheme "$scheme" \
            -destination "$DESTINATION" \
            -only-testing:"$target"
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
    find "$1" -name '*.png' | wc -l | tr -d ' '
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
    for suite in "${SUITES[@]}"; do
        IFS='|' read -r package scheme target _ <<< "$suite"
        directory=$(references_dir "$package" "$target")
        echo "==> deleting $directory"
        rm -rf "$directory"
        echo "==> recording $target (this run is expected to fail: every reference is missing)"
        if run_suite "$package" "$scheme" "$target"; then
            echo "snapshot-tests.sh: the recording run for $target PASSED, which it cannot do with" >&2
            echo "no references. Either the suite ran nothing, or a missing reference no longer" >&2
            echo "fails a run." >&2
            report_failure
            exit 70
        fi
        echo "==> recorded $(committed_references "$directory") references for $target; verifying below"
    done
fi

total=0
for suite in "${SUITES[@]}"; do
    IFS='|' read -r package scheme target minimum <<< "$suite"
    directory=$(references_dir "$package" "$target")

    if ! run_suite "$package" "$scheme" "$target"; then
        echo "snapshot-tests.sh: $target does not match. Rendered images and diffs are in" >&2
        echo "  $package/.build/snapshot-failures/" >&2
        echo "If the change is intended: scripts/snapshot-tests.sh --record, then review the diff." >&2
        report_failure
        exit 1
    fi

    count=$(executed_tests)
    if [[ -z "$count" ]]; then
        echo "snapshot-tests.sh: $target reported no test count at all — it executed nothing." >&2
        report_failure
        exit 70
    fi
    if (( count < minimum )); then
        echo "snapshot-tests.sh: only $count tests ran in $target, expected at least $minimum." >&2
        echo "A snapshot target that compiles to nothing passes; that is what this check is for." >&2
        report_failure
        exit 70
    fi

    references=$(committed_references "$directory")
    compared=$(compared_references)
    if [[ "$compared" != "$references" ]]; then
        echo "snapshot-tests.sh: $target compared $compared references, but its directory holds $references." >&2
        echo "  $directory" >&2
        echo "A suite that stops being run leaves its references behind, and a reference whose test was" >&2
        echo "deleted stays in the tree; both are green under a test count and neither is under this." >&2
        echo "If a reference is genuinely obsolete: scripts/snapshot-tests.sh --record." >&2
        report_failure
        exit 70
    fi

    echo "$target: $count tests passed, comparing all $references references."
    total=$(( total + references ))
done

echo "${#SUITES[@]} snapshot suites passed, comparing $total references."
