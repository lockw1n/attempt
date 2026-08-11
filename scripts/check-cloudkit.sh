#!/usr/bin/env bash
#
# T-0.33: the four CloudKit facts a test in the Persistence suite cannot check.
#
#   scripts/check-cloudkit.sh              # the gate
#   scripts/check-cloudkit.sh --self-test  # prove each check fires, in both directions
#
# `CloudKitCompatibilityTests` audits the schema against G-2.5 by walking SwiftData's own metadata,
# which is the mechanical half of DOD-0.4. It cannot see four things, and each of them is how the
# audit would stop being true without anyone noticing.
#
#   1  OUT-0.2, entitlement    Sync is off today *because the process has no CloudKit entitlement*,
#                              not because anything asks for it to be off. ModelConfiguration's
#                              cloudKitDatabase defaults to `.automatic`, which means "on if the
#                              entitlement is there" — measured: with no entitlement the whole
#                              mirroring mechanism is inert and a schema CloudKit rejects loads
#                              clean. So the day an iCloud capability is added for any reason, every
#                              existing container starts mirroring. The entitlement is the switch.
#
#   2  OUT-0.2, explicit       The other way to turn it on: naming a database. `.private(…)` and
#                              `.automatic` are bans, `.none` is the wanted spelling.
#
#   3  G-1.7                   No custom migration stage. `MigrationStage.custom` is the shape
#                              CloudKit mirroring cannot perform, and T-0.34 is about to write the
#                              first SchemaMigrationPlan — this is here before it, not after.
#
#   4  DOD-0.4                 Every @Model under Packages/Persistence/Sources/ is in the audited
#                              list in CloudKitCompatibilityTests.swift. "Every model passes" is a
#                              claim about a list, and a tenth entity that never joins the list
#                              passes by not being looked at. Checked by set comparison in both
#                              directions.
#
# Check 4 is a grep against a Swift array because SchemaV1 does not exist yet. When T-0.34 ships
# `SchemaV1.models`, the array becomes that list and this check keeps working — the markers are what
# is parsed, not the contents.
#
# THE POPULATION IS `git ls-files`, NOT A DIRECTORY WALK. Two reasons, and both were review
# findings. It is the same set of files CI checks out, so a violation cannot hide in a path this
# script forgot to name — the first version scanned three roots, and an entitlements file at the
# repo root was outside all of them. And a walk of `Packages/` descends into `Packages/*/.build`,
# where generated and copied sources will eventually match one of these regexes and fail the build
# for no reason at all. The self-test uses `find` over a scratch tree instead, because a scratch
# tree is not a git checkout; everything downstream of the file list is shared, so what the
# self-test exercises is the matching.

set -euo pipefail

cd "$(dirname "$0")/.."

SELF_TEST=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --self-test) SELF_TEST=1; shift ;;
        -h|--help)
            awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
            exit 0 ;;
        *) echo "check-cloudkit.sh: unknown option '$1'" >&2; exit 64 ;;
    esac
done

AUDIT_FILE="Packages/Persistence/Tests/PersistenceTests/CloudKitCompatibilityTests.swift"
ENTITY_DIR="Packages/Persistence/Sources/Persistence"

# Two alternatives, and each is self-tested alone. `com.apple.developer.icloud-*` is what an
# entitlements file carries; `com.apple.iCloud` is the SystemCapabilities key Xcode writes into the
# .pbxproj when the capability is switched on. The first version had a third that could not match
# anything — the pbxproj shape it was written for spans two lines and grep is line-based — and a
# fourth that the first alternative already subsumed. An untested alternative in a ban regex is the
# same defect as an unwatched gate.
ENTITLEMENT_RE='com\.apple\.developer\.(icloud|ubiquity)|com\.apple\.iCloud'

# `.none` is the spelling that turns it off, so only the two enabling cases are banned.
ENABLED_RE='cloudKitDatabase:[ \t]*\.(automatic|private)\b'

CUSTOM_MIGRATION_RE='MigrationStage\.custom|\.custom\([ \t]*forSourceVersion'

failures=0

fail() {
    printf '  FAIL  %-26s %s\n' "$1" "$2" >&2
    failures=$((failures + 1))
}

ok() { printf '  ok    %-26s %s\n' "$1" "$2"; }

# `grep -H` is not decoration. Given a single file grep omits the filename, and `code_only` below
# strips a `file:line:` prefix that would then not be there — so a commented-out violation in a
# one-file population would survive the filter and be reported as real. Found by review rather than
# by the self-test, which happened to use only multi-file trees; there is a one-file case now.
grep_files() {
    local re="$1" nocase="$2"
    shift 2
    (( $# == 0 )) && return 0
    if [[ "$nocase" == "i" ]]; then
        grep -nHiE "$re" "$@" 2>/dev/null || true
    else
        grep -nHE "$re" "$@" 2>/dev/null || true
    fi
}

# Drops lines that are prose. The same problem the custom SwiftLint rules solve with `match_kinds`,
# and not hypothetical: this repo documents the constructs it bans, so the audit's own header names
# `.private(…)` and T-0.34's will name `MigrationStage.custom`. This fired on its own documentation
# on the first run. A whole-line comment is dropped; a trailing comment on a real line is not, so
# `cloudKitDatabase: .automatic // temporarily` still fires. Both directions are self-tested.
code_only() {
    awk '{ body = $0; sub(/^[^:]*:[0-9]+:/, "", body); if (body !~ /^[ \t]*(\/\/|\*|\/\*)/) print }'
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

check_entitlements() {
    report "iCloud entitlement" "OUT-0.2: sync activation is out of scope. Found:" \
        "$(grep_files "$ENTITLEMENT_RE" i "$@")"
}

check_enabled() {
    report "cloudKitDatabase enabled" "OUT-0.2: the schema is compatible, not enabled. Found:" \
        "$(grep_files "$ENABLED_RE" x "$@" | code_only)"
}

check_custom_migration() {
    report "custom migration stage" "G-1.7: lightweight migrations only. Found:" \
        "$(grep_files "$CUSTOM_MIGRATION_RE" x "$@" | code_only)"
}

# Every `final class X` on or just after an `@Model`, which is the only shape this module uses.
declared_models() {
    grep -rhA2 '^@Model' --include='*.swift' "$1" 2>/dev/null \
        | grep -oE 'final class [A-Za-z0-9_]+' | awk '{ print $3 }' | sort -u
}

# Everything between the two markers, so the parse cannot drift onto some other array.
audited_models() {
    awk '/audited-models:begin/ { on = 1; next } /audited-models:end/ { on = 0 } on' "$1" \
        | grep -oE '[A-Za-z0-9_]+\.self' | sed 's/\.self$//' | sort -u
}

check_audit_covers_models() {
    local entity_dir="$1" audit_file="$2" declared audited missing extra
    declared="$(declared_models "$entity_dir")"
    audited="$(audited_models "$audit_file")"

    if [[ -z "$declared" ]]; then
        fail "audit coverage" "found no @Model under $entity_dir — the parse is broken, not the tree."
        return 1
    fi

    missing="$(comm -23 <(printf '%s\n' "$declared") <(printf '%s\n' "$audited"))"
    extra="$(comm -13 <(printf '%s\n' "$declared") <(printf '%s\n' "$audited"))"

    if [[ -n "$missing" ]]; then
        fail "audit coverage" "DOD-0.4: @Model types not in the audited list: $(tr '\n' ' ' <<<"$missing")"
    fi
    if [[ -n "$extra" ]]; then
        fail "audit coverage" "audited types that are not @Models under Sources: $(tr '\n' ' ' <<<"$extra")"
    fi
    [[ -z "$missing" && -z "$extra" ]]
}

# Reads a newline-separated list into the array `FILES`. Paths in this repo contain no spaces, and
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

    # Canned trees: every check in both directions, so neither a gate that rejects everything nor
    # one that rejects nothing can pass. `clean` spells all three banned constructs in prose, which
    # is the false positive this repo's own documentation would otherwise trip; `trailing` is its
    # mirror, a real call carrying a trailing comment; `lone` is a one-file population, which is
    # where the missing `grep -H` hid.
    mkdir -p "$scratch/clean" "$scratch/dirty" "$scratch/trailing" "$scratch/lone" "$scratch/entities"

    cat >"$scratch/clean/Config.swift" <<'EOF'
let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
// Prose naming the bans: cloudKitDatabase: .private("x"), cloudKitDatabase: .automatic,
/// MigrationStage.custom — none of these may fire, or the files documenting the rules break them.
 * MigrationStage.custom in a block comment's continuation line.
EOF
    cat >"$scratch/clean/App.entitlements" <<'EOF'
<key>com.apple.security.app-sandbox</key><true/>
EOF
    cat >"$scratch/dirty/Config.swift" <<'EOF'
let config = ModelConfiguration(schema: schema, cloudKitDatabase: .private("iCloud.com.example"))
let plan = MigrationStage.custom(forSourceVersion: SchemaV1.self)
EOF
    cat >"$scratch/dirty/App.entitlements" <<'EOF'
<key>com.apple.developer.icloud-container-identifiers</key>
EOF
    cat >"$scratch/capability.pbxproj" <<'EOF'
					com.apple.iCloud = {
						enabled = 1;
EOF
    cat >"$scratch/trailing/Trailing.swift" <<'EOF'
let c = ModelConfiguration(cloudKitDatabase: .automatic)  // temporarily, to try sync out
EOF
    cat >"$scratch/lone/Lone.swift" <<'EOF'
// cloudKitDatabase: .automatic named in a comment, in a population of exactly one file.
EOF
    cat >"$scratch/entities/Two.swift" <<'EOF'
@Model
final class AlphaEntity {}

@Model
final class BetaEntity {}
EOF
    cat >"$scratch/full-audit.swift" <<'EOF'
// audited-models:begin
let models = [AlphaEntity.self, BetaEntity.self]
// audited-models:end
let decoy = [GammaEntity.self]
EOF
    cat >"$scratch/short-audit.swift" <<'EOF'
// audited-models:begin
let models = [AlphaEntity.self]
// audited-models:end
EOF

    expect() {
        local label="$1" want="$2"; shift 2
        local before=$failures
        "$@" >/dev/null 2>&1 || true
        local fired=$(( failures > before ))
        failures=$before
        if [[ "$fired" == "$want" ]]; then
            printf '  ok    %-32s %s\n' "$label" "$([[ $want == 1 ]] && echo fires || echo passes)"
        else
            printf '  FAIL  %-32s expected fired=%s, got %s\n' "$label" "$want" "$fired" >&2
            failures=$((failures + 1))
        fi
    }

    expect_over() {
        local label="$1" want="$2" root="$3" check="$4"
        collect "$(find "$root" -type f 2>/dev/null | sort)"
        expect "$label" "$want" "$check" "${FILES[@]}"
    }

    echo "self-test — each check, in both directions"
    expect_over "iCloud entitlement" 1 "$scratch/dirty" check_entitlements
    expect_over "iCloud entitlement" 0 "$scratch/clean" check_entitlements
    # The pbxproj alternative alone — the entitlements-file alternative would otherwise cover for
    # it, and it would never once have been run.
    collect "$scratch/capability.pbxproj"
    expect "iCloud capability in pbxproj" 1 check_entitlements "${FILES[@]}"

    expect_over "cloudKitDatabase enabled" 1 "$scratch/dirty" check_enabled
    expect_over "cloudKitDatabase enabled" 0 "$scratch/clean" check_enabled
    expect_over "…with a trailing comment" 1 "$scratch/trailing" check_enabled
    expect_over "…in a one-file population" 0 "$scratch/lone" check_enabled

    expect_over "custom migration stage" 1 "$scratch/dirty" check_custom_migration
    expect_over "custom migration stage" 0 "$scratch/clean" check_custom_migration

    expect "audit coverage" 1 check_audit_covers_models "$scratch/entities" "$scratch/short-audit.swift"
    expect "audit coverage" 0 check_audit_covers_models "$scratch/entities" "$scratch/full-audit.swift"
    # A parse that finds nothing must fail rather than agree with an empty list.
    expect "audit coverage, empty parse" 1 check_audit_covers_models "$scratch/clean" "$scratch/full-audit.swift"

    echo
    if (( failures > 0 )); then
        echo "$failures self-test case(s) failed — this gate does not do what its header claims." >&2
        exit 1
    fi
    echo "all four checks fire, and none of them fires on a clean tree."
    exit 0
fi

if [[ ! -f "$AUDIT_FILE" ]]; then
    echo "check-cloudkit.sh: $AUDIT_FILE is missing — the audit it gates no longer exists." >&2
    exit 66
fi

echo "CloudKit: compatible, not enabled (OUT-0.2, G-1.7, DOD-0.4)"

# All four checks run. `&&`-chaining them, which the first version did across three roots, lets the
# first violation hide the rest — and a partial report is how the second one survives the fix.
# An empty population is a failure rather than a pass: it means the glob stopped matching, which is
# the same green-while-enforcing-nothing failure the whole script exists to prevent.
collect "$(git ls-files -- '*.entitlements' '*.plist' '*.pbxproj')"
entitlement_files=("${FILES[@]}")
if (( ${#entitlement_files[@]} == 0 )); then
    fail "iCloud entitlement" "no .entitlements/.plist/.pbxproj is tracked — the population is wrong."
elif check_entitlements "${entitlement_files[@]}"; then
    ok "iCloud entitlement" "none granted across ${#entitlement_files[@]} file(s) — .automatic stays inert"
fi

collect "$(git ls-files -- '*.swift')"
swift_files=("${FILES[@]}")
if (( ${#swift_files[@]} == 0 )); then
    fail "cloudKitDatabase enabled" "no Swift file is tracked — the population is wrong."
else
    if check_enabled "${swift_files[@]}"; then
        ok "cloudKitDatabase enabled" "clean across ${#swift_files[@]} tracked Swift file(s)"
    fi
    if check_custom_migration "${swift_files[@]}"; then
        ok "custom migration stage" "none — lightweight only"
    fi
fi

if check_audit_covers_models "$ENTITY_DIR" "$AUDIT_FILE"; then
    ok "audit coverage" "$(declared_models "$ENTITY_DIR" | wc -l | tr -d ' ') @Model types, all audited"
fi

echo
if (( failures > 0 )); then
    echo "$failures CloudKit check(s) failed." >&2
    exit 1
fi
