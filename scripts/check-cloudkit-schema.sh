#!/usr/bin/env bash
#
# TR-1.7: check the CloudKit schema, and prove the Production deployment actually landed.
#
#   scripts/check-cloudkit-schema.sh                                  # check both environments
#   scripts/check-cloudkit-schema.sh --allow-missing Entity[,Entity]  # naming each table left behind
#
# THE PROMOTION ITSELF IS NOT AUTOMATABLE, AND THIS SCRIPT DOES NOT PRETEND OTHERWISE. `cktool` has
# no promote or deploy subcommand: `import-schema --environment production` is refused by the server
# with "endpoint not applicable in the environment 'production'", and `reset-schema` runs the other
# way, resetting Development to match Production. Measured against a real container, not assumed —
# an earlier version of this script claimed to do the promotion and could not. Development -> Production
# happens in the CloudKit Console and nowhere else, which is what T-1.70's Goal said from the start.
#
# WHAT IS AUTOMATABLE IS THE EVIDENCE, and that is the half TR-1.7 actually worries about ("must not
# be forgotten"). The Console's "Deploy Schema Changes" button leaves nothing behind, so "I pressed
# Deploy" is not a claim anyone can check later. This turns it into a command whose output can be
# pasted into the task file, re-run after any schema change, and diffed.
#
# WHAT IT CHECKS, and why each part is here:
#
#   1  Development is not empty.       CoreData materialises the CD_* record types the first time a
#                                      mirrored build runs. Deploying an empty Development
#                                      environment promotes nothing and reports success.
#   2  Every @Model has a record type. A mirrored run that only ever touched four tables creates
#                                      four record types. The population is the same
#                                      `@Model`/`final class` parse `check-cloudkit.sh` uses for
#                                      DOD-0.4, so the two cannot disagree about what the schema is.
#                                      A table with no writing surface yet cannot be exercised into
#                                      existence, so --allow-missing exists — it takes entity names
#                                      rather than a bare --force, and prints them into the run's own
#                                      output, so the exception is a sentence in the record rather
#                                      than a silently lowered bar. A Production schema is ADDITIVE:
#                                      a record type left behind today can be deployed later, which
#                                      is what makes this exception safe where dropping a field is
#                                      not. It also fails if an excuse names a table that IS there,
#                                      since a stale excuse is how the next reader concludes a table
#                                      is unreachable long after it stopped being.
#   3  The two environments agree.     T-1.70's *Done when* says Production matches Development
#                                      field-for-field. A diff of the two exports is that sentence,
#                                      mechanically — and it is the only way to know the Console
#                                      button did what it looked like it did.
#
# NEITHER THE TEAM NOR THE CONTAINER IS SPELLED HERE. The container is read out of
# Attempt/Attempt.entitlements and the team out of the Xcode project, because those are the two
# files a build actually signs against — a script carrying its own copy would happily report on a
# container the app never opens. `check-cloudkit.sh` check 5 already pins the entitlement to the
# code, so reading from it inherits that agreement rather than adding a fourth copy to keep in sync.
#
# THE TOKEN IS NEVER AN ARGUMENT TO THIS SCRIPT. `cktool save-token --type management` prompts for
# it and puts it in the keychain; CLOUDKIT_MANAGEMENT_TOKEN works too. Mint one at
# CloudKit Console -> Settings -> Tokens. Passing it on a command line would put it in the shell
# history of whoever ran it.

set -euo pipefail

cd "$(dirname "$0")/.."

ENTITLEMENTS="Attempt/Attempt.entitlements"
PBXPROJ="Attempt.xcodeproj/project.pbxproj"
ENTITY_DIR="Packages/Persistence/Sources/Persistence"

usage() {
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

allow_missing=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --allow-missing)
            [[ $# -ge 2 ]] || {
                echo "check-cloudkit-schema.sh: --allow-missing needs entity names" >&2
                exit 64
            }
            allow_missing="$(tr ',' '\n' <<<"$2" | sed '/^$/d' | sort -u)"
            shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "check-cloudkit-schema.sh: unknown option '$1'" >&2; usage >&2; exit 64 ;;
    esac
done

# The container the app is entitled to open, taken from the entitlement rather than from here.
container="$(plutil -extract 'com\.apple\.developer\.icloud-container-identifiers.0' raw -o - \
    "$ENTITLEMENTS" 2>/dev/null || true)"
if [[ -z "$container" ]]; then
    echo "check-cloudkit-schema.sh: $ENTITLEMENTS names no iCloud container." >&2
    echo "  T-1.71 put it there; check-cloudkit.sh check 5 fails if it goes missing." >&2
    exit 66
fi

# The team the app is signed by. Unset until T-1.70 selects it, and without it cktool has no
# account to talk to.
team="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM = \([A-Z0-9]*\);.*/\1/p' "$PBXPROJ" | sort -u)"
if [[ -z "$team" ]]; then
    echo "check-cloudkit-schema.sh: DEVELOPMENT_TEAM is unset in $PBXPROJ." >&2
    echo "  Xcode -> target Attempt -> Signing & Capabilities -> Team writes it." >&2
    exit 66
elif [[ "$(wc -l <<<"$team")" -ne 1 ]]; then
    echo "check-cloudkit-schema.sh: build configurations disagree on DEVELOPMENT_TEAM:" >&2
    sed 's/^/  /' <<<"$team" >&2
    exit 65
fi

if [[ -z "${CLOUDKIT_MANAGEMENT_TOKEN:-}" ]] && ! xcrun cktool get-teams >/dev/null 2>&1; then
    cat >&2 <<'TOKEN'
check-cloudkit-schema.sh: no CloudKit management token.

  Mint one at CloudKit Console -> Settings -> Tokens (a management token, not a user token),
  then save it without putting it in your shell history:

      xcrun cktool save-token --type management

TOKEN
    exit 69
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

export_schema() {
    local environment="$1" out="$2"
    if ! xcrun cktool export-schema --team-id "$team" --container-id "$container" \
        --environment "$environment" --output-file "$out" >/dev/null 2>"$scratch/err"; then
        echo "  FAIL  export $environment" >&2
        sed 's/^/        /' "$scratch/err" >&2
        return 1
    fi
}

# CoreData names a mirrored entity CD_<EntityName>; the entity name is the @Model class name.
#
# BOTH PARSES END IN `|| true`, AND THAT IS NOT DEFENSIVENESS. Under `set -e` a grep that matches
# nothing returns 1, which fails the command substitution assigning it and kills the script *before*
# the "development schema is empty" check below can report anything — so the one guard that matters
# most on a fresh container could never fire, and the run died printing only its header. Found by
# running it against a real container rather than by reading it.
declared_record_types() {
    { grep -rhA2 '^@Model' --include='*.swift' "$ENTITY_DIR" 2>/dev/null \
        | grep -oE 'final class [A-Za-z0-9_]+' | awk '{ print "CD_" $3 }' | sort -u; } || true
}

# RECORD TYPE lines in an exported .ckdb, which is the schema's own spelling of its population.
# They are INDENTED inside `DEFINE SCHEMA`, so this must not anchor at the start of the line — the
# first version did, matched nothing on a perfectly good schema, and reported an empty environment.
#
# ONLY THE `CD_` TYPES. Every container also carries CloudKit's own built-in `Users`, which is not
# mirrored from any @Model and would make a 16-table schema report "17 record types" — the same
# number as the entity count, which is the one coincidence guaranteed to be misread here.
exported_record_types() {
    { grep -oE '[[:space:]]*RECORD TYPE CD_[A-Za-z0-9_]+' "$1" \
        | awk '{ print $3 }' | sort -u; } || true
}

echo "CloudKit schema: $container (team $team)"

failures=0
fail() { printf '  FAIL  %-22s %s\n' "$1" "$2" >&2; failures=$((failures + 1)); }
ok() { printf '  ok    %-22s %s\n' "$1" "$2"; }

export_schema development "$scratch/development.ckdb" || exit 1

declared="$(declared_record_types)"
present="$(exported_record_types "$scratch/development.ckdb")"

if [[ -z "$present" ]]; then
    fail "development schema" "empty — no mirrored build has run against this container yet."
    echo "        Run a Development build with sync on and log a set; CoreData creates the" >&2
    echo "        CD_* record types on the first mirrored save. There is nothing to deploy" >&2
    echo "        until it has, and deploying now would promote nothing and report success." >&2
    exit 1
fi
ok "development schema" "$(wc -l <<<"$present" | tr -d ' ') record type(s)"

missing="$(comm -23 <(printf '%s\n' "$declared") <(printf '%s\n' "$present"))"
# An excuse is written as the entity (TrainingMaxConfigEntity) and matched as the record type.
allowed="$(sed '/^$/d; s/^/CD_/' <<<"$allow_missing")"
unexcused="$(comm -23 <(sed '/^$/d' <<<"$missing") <(sed '/^$/d' <<<"$allowed"))"
stale="$(comm -13 <(sed '/^$/d' <<<"$missing") <(sed '/^$/d' <<<"$allowed"))"

if [[ -n "$unexcused" ]]; then
    fail "entity coverage" "@Model types with no record type: $(tr '\n' ' ' <<<"$unexcused")"
    echo "        The mirrored run did not touch every table. Exercise the missing ones and" >&2
    echo "        re-check before deploying a partial schema into Production. A table nothing in" >&2
    echo "        the app writes cannot be exercised at all — name it in --allow-missing." >&2
elif [[ -n "$missing" ]]; then
    ok "entity coverage" "left behind on purpose: $(sed 's/^CD_//' <<<"$missing" | tr '\n' ' ')"
    echo "        Production is additive, so a later deploy can add it once something writes the" >&2
    echo "        table; nothing about today's deployment forecloses that." >&2
else
    ok "entity coverage" "all $(wc -l <<<"$declared" | tr -d ' ') @Model types present"
fi

if [[ -n "$stale" ]]; then
    fail "entity coverage" \
        "--allow-missing names a table that IS present: $(sed 's/^CD_//' <<<"$stale" | tr '\n' ' ')"
fi

export_schema production "$scratch/production.ckdb" || exit 1

# Field-for-field, which is *Done when*'s own wording. A CloudKit export is deterministic in
# ordering, so a plain diff is the comparison rather than an approximation of it.
if diff -u "$scratch/development.ckdb" "$scratch/production.ckdb" >"$scratch/diff"; then
    ok "environments agree" "production matches development field-for-field"
else
    fail "environments agree" "production differs from development:"
    sed 's/^/        /' "$scratch/diff" >&2
    cat >&2 <<DEPLOY

  The deployment is a Console step; nothing here can perform it.

      1  open https://icloud.developer.apple.com
      2  pick the container $container
      3  Schema -> Deploy Schema Changes -> review the diff -> Deploy
      4  re-run this script; it passes only once Production matches

DEPLOY
fi

echo
if (( failures > 0 )); then
    echo "$failures CloudKit schema check(s) failed." >&2
    exit 1
fi
echo "schema deployed and verified — record the date in docs/phase-1/tasks/T-1.70-*.md."
