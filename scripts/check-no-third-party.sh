#!/usr/bin/env bash
#
# G-5.1: no third-party code in the tree, and therefore no third-party SDK to receive an identifier.
#
#   scripts/check-no-third-party.sh              # the gate
#   scripts/check-no-third-party.sh --self-test  # prove each check fires, in both directions
#
# T-1.81 was to bring TelemetryDeck in and did not — TR-1.11 is deferred rather than built, and the
# reasoning is in that task's file. What the deferral leaves behind is a property nothing was
# holding: every dependency in this repo is a local path package, so no third party is in a position
# to be told anything, and G-5.1 is satisfied by construction rather than by a payload audit. That
# is a much stronger guarantee than "the payloads we send are the right shape", and it is also the
# kind that decays silently — one `.package(url:` is all it takes, in a diff about something else.
#
# It backs two sentences that ship inside the binary and cannot be corrected server-side (G-5.3,
# T-1.63 put the policy in the app rather than behind a link):
#
#   settings.about.acknowledgements.code   "Attempt bundles no third-party code."
#   settings.about.privacy.tracking        "There is no analytics, no advertising and no tracking."
#
# So this is the About screen's fact-checker as much as a dependency policy. A remote package that
# lands without either sentence moving makes the app's own privacy policy false, which is the failure
# G-5.3 is written to prevent at every submission.
#
#   1  manifests    No `.package(url:` in any tracked Package.swift. This is how a package under
#                   Packages/ acquires a remote dependency, and the app links it transitively
#                   without the .xcodeproj mentioning anything.
#   2  project      No XCRemoteSwiftPackageReference in any tracked .pbxproj, and no resolved
#                   dependency pinned in a Package.resolved. This is the other route in — Xcode's
#                   own "Add Package Dependency", which touches neither manifest.
#
# Both are needed and neither subsumes the other: check 1 cannot see a dependency added through
# Xcode, and check 2 cannot see one added to a package manifest, because a local package's remote
# dependencies never appear in the project file.
#
# THE POPULATION IS `git ls-files`, for check-cloudkit.sh's two reasons: it is the same set CI
# checks out, and a directory walk descends into Packages/*/.build, where a checked-out dependency
# of the toolchain's own would match check 1 and fail the build for no reason.
#
# WHEN THIS GATE IS SUPPOSED TO FAIL: the session that takes TR-1.11 (or any other third-party
# dependency) out of deferral deletes it, and rewrites the two sentences above in the same commit.
# Do not add an allowlist entry — the point is that the two are one decision.

set -euo pipefail

cd "$(dirname "$0")/.."

SELF_TEST=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --self-test) SELF_TEST=1; shift ;;
        -h|--help)
            awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
            exit 0 ;;
        *) echo "check-no-third-party.sh: unknown option '$1'" >&2; exit 64 ;;
    esac
done

# `.package(url:` with any spacing. `.package(path:` is the local form and is what this repo uses
# everywhere; only the remote spelling is banned.
REMOTE_MANIFEST_RE='\.package\([ \t]*url[ \t]*:'

# Xcode's remote reference, plus the `pins` array a Package.resolved carries once one is resolved.
# The second is not redundant: a resolved file can outlive the reference that produced it, and it is
# the artefact that actually names what was fetched.
REMOTE_PROJECT_RE='XCRemoteSwiftPackageReference|"pins"[ \t]*:'

failures=0

fail() {
    printf '  FAIL  %-22s %s\n' "$1" "$2" >&2
    failures=$((failures + 1))
}

ok() { printf '  ok    %-22s %s\n' "$1" "$2"; }

# `grep -H` so a one-file population still carries a filename, which `code_only` strips a prefix
# from. check-cloudkit.sh shipped without it and a commented-out violation survived the filter.
grep_files() {
    local re="$1"
    shift
    (( $# == 0 )) && return 0
    grep -nHE "$re" "$@" 2>/dev/null || true
}

# Drops whole-line comments, so this script's own header and a manifest's prose cannot fire it —
# and this repo's manifests are mostly prose. A trailing comment on a real line still fires. Same
# filter as check-cloudkit.sh's, kept local rather than shared: two callers is not yet a library,
# and a sourced helper would put the awk further from the regex it guards.
code_only() {
    awk '{ body = $0; sub(/^[^:]*:[0-9]+:/, "", body); if (body !~ /^[ \t]*(\/\/|\*|\/\*|#)/) print }'
}

report() {
    local label="$1" message="$2" hits="$3"
    if [[ -n "$hits" ]]; then
        fail "$label" "$message"
        sed 's/^/          /' <<<"$hits" >&2
        return 1
    fi
    return 0
}

check_manifests() {
    report "remote in manifest" \
        "G-5.1: a package manifest names a remote dependency. Found:" \
        "$(grep_files "$REMOTE_MANIFEST_RE" "$@" | code_only)"
}

check_project() {
    report "remote in project" \
        "G-5.1: the Xcode project names a remote package. Found:" \
        "$(grep_files "$REMOTE_PROJECT_RE" "$@" | code_only)"
}

# Reads a newline-separated list into `FILES`. No path in this repo contains a space, and
# `git ls-files` would quote one that did, so a plain read loop is honest here.
collect() {
    FILES=()
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] && FILES+=("$line")
    done <<<"${1:-}"
}

if (( SELF_TEST )); then
    scratch="$(mktemp -d)"
    trap 'rm -rf "$scratch"' EXIT

    mkdir -p "$scratch/clean" "$scratch/dirty" "$scratch/trailing" "$scratch/lone"

    # The shape this repo is actually in, plus prose naming the banned spelling — which is what the
    # file you are reading does, and what every manifest here would do if it explained the rule.
    cat >"$scratch/clean/Package.swift" <<'EOF'
dependencies: [
    .package(path: "../../PowerliftingCore"),
    // Never .package(url: "https://github.com/example/Thing.git", from: "1.0.0") — see G-5.1.
]
EOF
    cat >"$scratch/clean/project.pbxproj" <<'EOF'
packageReferences = (
    D34 /* XCLocalSwiftPackageReference "Packages/PowerliftingCore" */,
);
EOF
    cat >"$scratch/dirty/Package.swift" <<'EOF'
dependencies: [
    .package(url: "https://github.com/TelemetryDeck/SwiftSDK.git", from: "2.14.2"),
]
EOF
    cat >"$scratch/dirty/project.pbxproj" <<'EOF'
D35 /* XCRemoteSwiftPackageReference "SwiftSDK" */ = {
    isa = XCRemoteSwiftPackageReference;
EOF
    # A Package.resolved alone, which is check 2's second alternative. It would never have been run
    # against the pbxproj fixture above, since the first alternative already matches there.
    cat >"$scratch/lone/Package.resolved" <<'EOF'
{
  "pins" : [
    { "identity" : "swiftsdk" }
  ]
}
EOF
    # A real dependency carrying a trailing comment — the mirror of the clean case, and the one a
    # naive "drop any line mentioning a comment" filter would wave through.
    cat >"$scratch/trailing/Package.swift" <<'EOF'
    .package(url: "https://github.com/example/Thing.git", from: "1.0.0"),  // just to try it out
EOF

    expect() {
        local label="$1" want="$2"; shift 2
        local before=$failures
        "$@" >/dev/null 2>&1 || true
        local fired=$(( failures > before ))
        failures=$before
        if [[ "$fired" == "$want" ]]; then
            printf '  ok    %-34s %s\n' "$label" "$([[ $want == 1 ]] && echo fires || echo passes)"
        else
            printf '  FAIL  %-34s expected fired=%s, got %s\n' "$label" "$want" "$fired" >&2
            failures=$((failures + 1))
        fi
    }

    echo "self-test — each check, in both directions"
    collect "$scratch/dirty/Package.swift"
    expect "remote in manifest" 1 check_manifests "${FILES[@]}"
    collect "$scratch/clean/Package.swift"
    expect "…local path only" 0 check_manifests "${FILES[@]}"
    collect "$scratch/trailing/Package.swift"
    expect "…with a trailing comment" 1 check_manifests "${FILES[@]}"

    collect "$scratch/dirty/project.pbxproj"
    expect "remote in project" 1 check_project "${FILES[@]}"
    collect "$scratch/clean/project.pbxproj"
    expect "…local references only" 0 check_project "${FILES[@]}"
    collect "$scratch/lone/Package.resolved"
    expect "…a resolved file's pins alone" 1 check_project "${FILES[@]}"

    echo
    if (( failures > 0 )); then
        echo "$failures self-test case(s) failed — this gate does not do what its header claims." >&2
        exit 1
    fi
    echo "both checks fire, and neither fires on a clean tree."
    exit 0
fi

echo "third-party code: none, so no SDK is in a position to be told anything (G-5.1, G-5.3)"

# An empty population is a failure rather than a pass: it means the pathspec stopped matching, which
# is the green-while-enforcing-nothing shape every gate here is written against.
collect "$(git ls-files -- '*/Package.swift' 'Package.swift')"
manifests=("${FILES[@]}")
if (( ${#manifests[@]} == 0 )); then
    fail "remote in manifest" "no Package.swift is tracked — the population is wrong."
elif check_manifests "${manifests[@]}"; then
    ok "remote in manifest" "${#manifests[@]} manifest(s), local paths only"
fi

collect "$(git ls-files -- '*.pbxproj' '*.resolved')"
project=("${FILES[@]}")
if (( ${#project[@]} == 0 )); then
    fail "remote in project" "no .pbxproj is tracked — the population is wrong."
elif check_project "${project[@]}"; then
    ok "remote in project" "${#project[@]} project file(s), no remote package"
fi

echo
if (( failures > 0 )); then
    echo "$failures third-party check(s) failed." >&2
    echo "If this is deliberate: the About screen's acknowledgements and tracking sentences are" >&2
    echo "now false and have to move in the same commit (G-5.3). See this script's header." >&2
    exit 1
fi
