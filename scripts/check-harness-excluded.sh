#!/usr/bin/env bash
#
# T-0.60 / OUT-0.1: the debug harness is not in the app's build graph.
#
#   scripts/check-harness-excluded.sh
#
# WHY THIS EXISTS. `DOD-0.3` wants a harness and `OUT-0.1` wants it out of release builds. The
# mechanism is structural rather than a build setting: Packages/DebugHarness publishes an
# executable product and no library, so the app target cannot link it. That is a one-line property
# of a manifest, and a one-line property is exactly the kind that gets relaxed by someone who wants
# to reuse the report formatter in a screen.
#
# The three checks are the three ways the exclusion could be lost, cheapest first. None of them
# needs Xcode, so this runs anywhere.

set -euo pipefail

cd "$(dirname "$0")/.."

MANIFEST="Packages/DebugHarness/Package.swift"
PROJECT="Attempt.xcodeproj/project.pbxproj"

failures=0

fail() {
    printf '  FAIL  %s\n' "$1"
    failures=$((failures + 1))
}

if [[ ! -f "$MANIFEST" ]]; then
    echo "error: $MANIFEST not found — has the harness been removed? Delete this script too." >&2
    exit 66
fi

if grep -qE '\.library\(' "$MANIFEST"; then
    fail "$MANIFEST publishes a library product; only an executable one may be published."
else
    printf '  ok    no library product in %s\n' "$MANIFEST"
fi

if grep -q 'DebugHarness' "$PROJECT"; then
    fail "$PROJECT references DebugHarness; the app must not depend on the harness."
else
    printf '  ok    %s does not reference the harness\n' "$PROJECT"
fi

if grep -rqE '\bimport[ \t]+(DebugHarness|HarnessCommand)\b' Attempt --include='*.swift'; then
    fail "an app source imports the harness."
else
    printf '  ok    no app source imports the harness\n'
fi

echo
if (( failures > 0 )); then
    cat >&2 <<EOF
$failures check(s) failed: the debug harness has reached the app.

OUT-0.1 puts everything beyond a throwaway harness out of scope for Phase 0, and DOD-0.3's harness
is excluded from release builds by not being linkable from the app at all. If the code being
reached for is worth keeping, move it into a package the app may depend on — do not widen this one.
EOF
    exit 1
fi

echo "the debug harness is excluded from the app build."
