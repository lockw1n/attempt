#!/usr/bin/env bash
#
# T-0.03 / G-6.4: assert the app target's Swift build settings have not drifted.
#
#   scripts/audit-app-build-settings.sh
#
# WHY THIS EXISTS. `TR-0.6.3` (generate the project from a manifest) was deferred to Phase 1, so
# `Attempt.xcodeproj` stays hand-managed and these four settings live in `.pbxproj` — a file where
# a regression is effectively invisible in review. Nobody reads a pbxproj diff and notices
# SWIFT_VERSION going back to 5.0. This script is the compensating control for that deferral.
#
# It is worth having even if the generator is adopted later: a manifest states intent, whereas
# `-showBuildSettings` reports what the build system actually resolved. Those are not the same
# claim, and it is the second one that decides whether G-6.4 holds.
#
# It deliberately checks only the app target. The packages carry their equivalents in
# `Package.swift`, where they are already reviewable in a normal diff, and T-0.03 verified
# separately that the app's MainActor default does not leak into them (TR-0.1.3).

set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="Attempt.xcodeproj"
SCHEME="Attempt"
DESTINATION="generic/platform=iOS Simulator"

# setting name : required value
EXPECTED=(
    "SWIFT_VERSION:6.0"
    "SWIFT_STRICT_CONCURRENCY:complete"
    "SWIFT_TREAT_WARNINGS_AS_ERRORS:YES"
    "SWIFT_DEFAULT_ACTOR_ISOLATION:MainActor"
)

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "error: xcodebuild not found — this script needs Xcode." >&2
    exit 1
fi

echo "resolving build settings for $SCHEME ..."
settings="$(xcodebuild -showBuildSettings \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" 2>/dev/null)" || {
    echo "error: xcodebuild -showBuildSettings failed." >&2
    exit 1
}

failures=0

for pair in "${EXPECTED[@]}"; do
    name="${pair%%:*}"
    want="${pair##*:}"

    # `-showBuildSettings` prints "    NAME = value"; take the first match and trim.
    got="$(grep -E "^[[:space:]]*${name} = " <<<"$settings" | head -n 1 | sed -E 's/^[[:space:]]*[A-Z_]+ = //' | tr -d '[:space:]')"

    if [[ -z "$got" ]]; then
        printf '  FAIL  %-34s not set at all (expected %s)\n' "$name" "$want"
        failures=$((failures + 1))
    elif [[ "$got" == "$want" ]]; then
        printf '  ok    %-34s %s\n' "$name" "$got"
    else
        printf '  FAIL  %-34s is %s, expected %s\n' "$name" "$got" "$want"
        failures=$((failures + 1))
    fi
done

echo
if (( failures > 0 )); then
    cat >&2 <<EOF
$failures app-target build setting(s) have drifted.

These are G-6.4's gate for the app target and were set deliberately in T-0.06. If a change was
intended, update this script and say why in docs/phase-0/tasks/T-0.03-generate-xcode-project.md.
Do not "fix" it by relaxing the expectation without recording the reason — that is the exact
silent regression this script exists to catch.
EOF
    exit 1
fi

echo "all ${#EXPECTED[@]} app-target build settings match."
