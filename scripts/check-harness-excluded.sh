#!/usr/bin/env bash
#
# T-0.60 / OUT-0.1: the debug harness is not in the app's build graph.
#
#   scripts/check-harness-excluded.sh
#   scripts/check-harness-excluded.sh --self-test   # prove each check fires, in both directions
#
# WHY THIS EXISTS. `DOD-0.3` wants a harness and `OUT-0.1` wants it out of release builds. The
# exclusion is structural rather than a build setting, and Packages/DebugHarness/Package.swift is
# where that mechanism is written down. It is a one-line property of a manifest, and a one-line
# property is exactly the kind that gets relaxed by someone who wants to reuse the report formatter
# in a screen.
#
# The three checks are the three ways the exclusion could be lost, cheapest first. None of them
# needs Xcode, so this runs anywhere.
#
# EVERY PATH IS ASSERTED TO EXIST BEFORE IT IS SEARCHED, and each check takes the path it searches
# rather than reading a global. `grep` over a path that is not there simply finds no match, so a
# check whose target had been renamed would report `ok` — the one failure mode a gate must not
# have, because it is indistinguishable from success. Taking the path as an argument is also what
# lets `--self-test` run this identical code over a scratch tree.

set -euo pipefail

SELF_TEST=0
while (( $# )); do
    case "$1" in
        --self-test) SELF_TEST=1; shift ;;
        *) echo "check-harness-excluded.sh: unknown argument: $1" >&2; exit 64 ;;
    esac
done

cd "$(dirname "$0")/.."

MANIFEST="Packages/DebugHarness/Package.swift"
PROJECT="Attempt.xcodeproj/project.pbxproj"
APP_SOURCES="Attempt"

failures=0

fail() {
    printf '  FAIL  %s\n' "$1"
    failures=$((failures + 1))
}

ok() {
    printf '  ok    %s\n' "$1"
}

check_no_library_product() {
    local manifest="$1"
    if [[ ! -f "$manifest" ]]; then
        fail "$manifest is missing, so this check searched nothing. If the harness has been deleted — it is disposable, and that is a legitimate end state — delete this script and its CI steps with it."
        return
    fi
    if grep -qE '\.library\(' "$manifest"; then
        fail "$manifest publishes a library product; only an executable one may be published."
    else
        ok "no library product in $manifest"
    fi
}

check_project_does_not_reference_harness() {
    local project="$1"
    if [[ ! -f "$project" ]]; then
        fail "$project is missing, so this check searched nothing."
        return
    fi
    if grep -q 'DebugHarness' "$project"; then
        fail "$project references DebugHarness; the app must not depend on the harness."
    else
        ok "$project does not reference the harness"
    fi
}

check_no_app_source_imports_harness() {
    local sources="$1"
    if [[ ! -d "$sources" ]]; then
        fail "$sources/ is missing, so this check searched nothing."
        return
    fi
    if grep -rqE '\bimport[ \t]+(DebugHarness|HarnessCommand)\b' "$sources" --include='*.swift'; then
        fail "an app source under $sources/ imports the harness."
    else
        ok "no app source under $sources/ imports the harness"
    fi
}

if (( SELF_TEST )); then
    scratch="$(mktemp -d)"
    trap 'rm -rf "$scratch"' EXIT

    mkdir -p "$scratch/clean" "$scratch/dirty"

    cat >"$scratch/clean/Package.swift" <<'EOF'
products: [.executable(name: "attempt-harness", targets: ["HarnessCommand"])]
EOF
    cat >"$scratch/dirty/Package.swift" <<'EOF'
products: [
    .executable(name: "attempt-harness", targets: ["HarnessCommand"]),
    .library(name: "DebugHarness", targets: ["DebugHarness"]),
]
EOF
    printf 'A0B1C2D3 /* Attempt */ = {isa = PBXNativeTarget; };\n' >"$scratch/clean/project.pbxproj"
    printf 'A0B1C2D3 /* DebugHarness */ = {isa = XCSwiftPackageProductDependency; };\n' \
        >"$scratch/dirty/project.pbxproj"
    mkdir -p "$scratch/clean/Attempt" "$scratch/dirty/Attempt"
    printf 'import SwiftUI\n' >"$scratch/clean/Attempt/AttemptApp.swift"
    printf 'import SwiftUI\nimport DebugHarness\n' >"$scratch/dirty/Attempt/AttemptApp.swift"

    selftest_failures=0

    # Runs one check and reports whether it fired, without letting it move the real counter.
    expect() {
        local label="$1" want="$2" check="$3"
        shift 3
        local before="$failures"
        "$check" "$@" >/dev/null
        local fired=0
        if (( failures > before )); then fired=1; fi
        failures="$before"
        if (( fired == want )); then
            ok "$label"
        else
            printf '  FAIL  %s — expected fired=%d, got %d\n' "$label" "$want" "$fired"
            selftest_failures=$((selftest_failures + 1))
        fi
    }

    echo "self-test — each check in both directions, plus a target that has moved"
    expect "a library product is rejected"        1 check_no_library_product "$scratch/dirty/Package.swift"
    expect "an executable-only manifest passes"   0 check_no_library_product "$scratch/clean/Package.swift"
    expect "a moved manifest is not a pass"       1 check_no_library_product "$scratch/gone/Package.swift"

    expect "a project naming the harness fails"   1 check_project_does_not_reference_harness \
        "$scratch/dirty/project.pbxproj"
    expect "a project not naming it passes"       0 check_project_does_not_reference_harness \
        "$scratch/clean/project.pbxproj"
    expect "a moved project is not a pass"        1 check_project_does_not_reference_harness \
        "$scratch/gone/project.pbxproj"

    expect "an app source importing it fails"     1 check_no_app_source_imports_harness "$scratch/dirty/Attempt"
    expect "an app source not importing passes"   0 check_no_app_source_imports_harness "$scratch/clean/Attempt"
    expect "a moved source tree is not a pass"    1 check_no_app_source_imports_harness "$scratch/gone/Attempt"

    echo
    if (( selftest_failures > 0 )); then
        echo "$selftest_failures self-test case(s) failed — this gate does not do what its header claims." >&2
        exit 1
    fi
    echo "all three checks fire, none fires on a clean tree, and none reports a missing target as a pass."
    exit 0
fi

check_no_library_product "$MANIFEST"
check_project_does_not_reference_harness "$PROJECT"
check_no_app_source_imports_harness "$APP_SOURCES"

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
