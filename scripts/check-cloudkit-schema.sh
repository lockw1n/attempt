#!/usr/bin/env bash
#
# TR-1.7: check the CloudKit schema, and prove the Production deployment actually landed.
#
#   scripts/check-cloudkit-schema.sh                                  # check both environments
#   scripts/check-cloudkit-schema.sh --offline                        # the chain gate; no network
#   scripts/check-cloudkit-schema.sh --self-test                      # prove check 3 fires
#   scripts/check-cloudkit-schema.sh --refresh                        # re-record the snapshot
#   scripts/check-cloudkit-schema.sh --complete <file>                # write the schema to import
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
#   3  Every @Model PROPERTY has a     T-1.95. Checks 1 and 2 ask about TABLES, and on 2026-09-11
#      field, of the declared type.     this script reported "production matches development
#                                      field-for-field" while sync was dead: 23 columns across all
#                                      17 record types had no field in either environment, 16 of
#                                      them CD_deletedAt. NSPersistentCloudKitContainer creates a
#                                      field LAZILY, on the first export of a row holding a non-nil
#                                      value for it — so the deployed schema is not the model's, it
#                                      is the set of columns that have happened to hold a value. A
#                                      Production schema is deploy-only, so the client cannot create
#                                      the missing one; the mirroring delegate traps, never
#                                      initialises, and NEITHER AN IMPORT NOR AN EXPORT EVER RUNS
#                                      AGAIN on that install. The lifter sees "Not synced yet",
#                                      which is what a fresh install says too.
#   4  The two environments agree.     T-1.70's *Done when* says Production matches Development
#                                      field-for-field. A diff of the two exports is that sentence,
#                                      mechanically — and it is the only way to know the Console
#                                      button did what it looked like it did.
#   5  The snapshot is the deployment.  $SNAPSHOT is the deployed schema, committed. Checks 1-4 need
#                                      a network round trip and a management token, which is not
#                                      what the verification chain is for — so --offline runs check
#                                      3 against the snapshot instead, at grep cost, and this check
#                                      is what stops the snapshot drifting away from the container
#                                      it claims to describe.
#
# --offline IS THE CHAIN ENTRY, AND IT EXISTS FOR THE SECOND DECAY MECHANISM RATHER THAN THE FIRST.
# T-1.70 deployed correctly on 2026-09-06; Phase 1.7 and T-1.93 then added columns behind it and
# nothing re-ran this script for five days. A missing field is invisible from inside the app, costs
# nothing until the first row carries a value, and then ends that install's sync permanently — so
# the gate has to be one that runs without being remembered. It reads two files and no network.
# A diff that adds a @Model property fails it; the fix is to deploy and then --refresh.
#
# --complete IS THE REPAIR, AND IT IS WHY NOTHING HERE CALLS initializeCloudKitSchema. That method
# is on NSPersistentCloudKitContainer, and SwiftData exposes no way to obtain one: measured against
# the iPhoneOS 26.5 SDK, its entire interface carries no NSManagedObjectModel bridge, so the
# "supported" route is unreachable from this app at all. What IS supported is importing a schema
# file into Development — so --complete writes the snapshot with every missing field added, each
# field's type spelling COPIED from an existing column of the same Swift type rather than guessed,
# and `cktool import-schema` applies it. Validated against the real container on 2026-09-12.
# It needs no app build and no entitlement change, which is the answer to "a build that can reach
# Development is a prerequisite for ever evolving the schema": it is not.
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
SNAPSHOT="Config/cloudkit-schema.ckdb"

usage() {
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

allow_missing=""
mode="networked"
complete_out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --allow-missing)
            [[ $# -ge 2 ]] || {
                echo "check-cloudkit-schema.sh: --allow-missing needs entity names" >&2
                exit 64
            }
            allow_missing="$(tr ',' '\n' <<<"$2" | sed '/^$/d' | sort -u)"
            shift 2 ;;
        --offline) mode="offline"; shift ;;
        --self-test) mode="self-test"; shift ;;
        --refresh) mode="refresh"; shift ;;
        --complete)
            [[ $# -ge 2 ]] || {
                echo "check-cloudkit-schema.sh: --complete needs an output path" >&2
                exit 64
            }
            mode="complete"; complete_out="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "check-cloudkit-schema.sh: unknown option '$1'" >&2; usage >&2; exit 64 ;;
    esac
done

# CoreData names a mirrored entity CD_<EntityName> and a mirrored attribute CD_<propertyName>; the
# entity name is the @Model class name.
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

# EVERY STORED PROPERTY OF EVERY @Model, AS THE FIELD IT MIRRORS TO, WITH THE TYPE CLOUDKIT GIVES IT.
# Three columns, tab-separated: record type, field name, column spelling.
#
# THE SPELLINGS ARE COPIED, NOT INVENTED. Each one is what a real export of this container already
# carries for a column of that Swift type — CD_deletedAt on CD_PersonalRecordCacheEntity is the
# TIMESTAMP precedent, CD_weightGrams the INT64 one, and so on. That is what makes --complete safe
# to import: a field whose CloudKit type disagreed with what CoreData will later try to write would
# fail exactly as the missing one does, one export later.
#
# AN UNMAPPED SWIFT TYPE IS A FAILURE, NOT A SKIP. A property this table has no spelling for is a
# property nothing here can check, and silently dropping it is how check 3 would come to report
# green over the next CD_deletedAt. `SchemaV1` is lightweight-migration-only, so the set of legal
# column types is small and closed; a new one is a schema decision, and it is meant to stop here.
#
# AND NEITHER IS AN UNREADABLE DECLARATION, WHICH IS THE SAME RULE ONE STEP EARLIER. The first
# version of this parse matched one exact shape — access modifiers, `var`, a name, a type
# annotation — and every declaration that missed it was dropped without a word: `var restSeconds =
# 90` (a perfectly ordinary mirrored column, since nothing in this repo requires an annotation) and
# `@Attribute(.externalStorage) var blob: Data = Data()` both left the gate reporting green over a
# column with no field, which is the exact defect T-1.95 exists to end. So EVERY declaration at the
# body level is now classified into one of five, and the fifth is a failure:
#
#   stored     a name, a type, and no brace before the `=`  ->  the field it mirrors to
#   @Transient declared not to mirror                       ->  skipped, and it IS a skip
#   computed   a brace before any `=`                       ->  skipped; not a column
#   static     not an instance property                     ->  skipped; not a column
#   anything else                                           ->  UNPARSED, and check 3 fails
#
# The four skips are each decidable from the line itself, which is what makes them safe; the fifth
# is the residue, and a residue that fails is the only version of this parse that can be trusted to
# have seen every column. Comment lines are dropped before any of it — the self-test's fixture names
# `var decoy: Int` inside a doc comment for exactly that reason.
declared_fields() {
    awk '
        BEGIN {
            FS = "\n"
            spell["Date"]     = "TIMESTAMP QUERYABLE SORTABLE"
            spell["Int"]      = "INT64 QUERYABLE SORTABLE"
            spell["Bool"]     = "INT64 QUERYABLE SORTABLE"
            spell["Double"]   = "DOUBLE QUERYABLE SORTABLE"
            spell["UUID"]     = "STRING QUERYABLE SEARCHABLE SORTABLE"
            spell["String"]   = "STRING QUERYABLE SEARCHABLE SORTABLE"
            spell["Data"]     = "BYTES QUERYABLE SORTABLE"
            spell["[Int]"]    = "BYTES QUERYABLE SORTABLE"
            spell["[Double]"] = "BYTES QUERYABLE SORTABLE"
            spell["[String]"] = "BYTES QUERYABLE SORTABLE"
            spell["[UUID]"]   = "BYTES QUERYABLE SORTABLE"
        }
        /^@Model/ { pending = 1; next }
        pending && /^final class [A-Za-z0-9_]+/ {
            entity = $0
            sub(/^final class /, "", entity)
            sub(/[^A-Za-z0-9_].*$/, "", entity)
            inside = 1; pending = 0; attrs = ""; next
        }
        inside && /^}/ { inside = 0 }
        # Body level only: exactly four spaces, then something. A nested type or a closure indents
        # further and declares nothing this schema carries.
        inside && /^    [^ ]/ {
            line = $0
            sub(/^    /, "", line)
            # A comment, even one that names a property in prose.
            if (line ~ /^\/\//) { attrs = ""; next }
            # An attribute on its own line belongs to the declaration under it.
            if (line ~ /^@[A-Za-z0-9_]+(\([^)]*\))?[[:space:]]*$/) { attrs = attrs line " "; next }
            head = attrs line
            attrs = ""
            if (head !~ /(^|[[:space:]])var[[:space:]]/) next
            # NOT MIRRORED, so it owes no field. The one skip that is about CoreData rather than
            # about Swift, and the reason this runs before the modifiers are stripped.
            if (head ~ /(^|[[:space:]])@Transient([[:space:](]|$)/) next
            rest = head
            while (match(rest, /^@[A-Za-z0-9_]+(\([^)]*\))?[[:space:]]+/)) {
                rest = substr(rest, RSTART + RLENGTH)
            }
            while (match(rest, /^(private\(set\)|private|public|internal|fileprivate|package|final|lazy|nonisolated)[[:space:]]+/)) {
                rest = substr(rest, RSTART + RLENGTH)
            }
            if (rest ~ /^static[[:space:]]/) next
            if (rest !~ /^var [A-Za-z0-9_]+[[:space:]]*:/) {
                printf "CD_%s\tCD_?\tUNPARSED:%s\n", entity, line
                next
            }
            name = rest
            sub(/^var /, "", name)
            sub(/[[:space:]]*:.*$/, "", name)
            type = rest
            sub(/^[^:]*:[[:space:]]*/, "", type)
            # A brace before any assignment is a computed property; an assignment first is a stored
            # one with a default, which every column here has (SchemaV1 rule 1).
            brace = index(type, "{")
            assign = index(type, "=")
            if (brace > 0 && (assign == 0 || brace < assign)) next
            if (assign > 0) type = substr(type, 1, assign - 1)
            sub(/[[:space:]]+$/, "", type)
            sub(/\?$/, "", type)
            if (type == "") {
                printf "CD_%s\tCD_%s\tUNPARSED:%s\n", entity, name, line
                next
            }
            printf "CD_%s\tCD_%s\t%s\n", entity, name, (type in spell ? spell[type] : "UNMAPPED:" type)
        }
        inside { attrs = "" }
    ' "$@" | sort -u
}

# The Swift files the parse above runs over: the tracked entity sources, or whatever the self-test
# hands it. `git ls-files` rather than a walk, for `check-cloudkit.sh`'s reason — it is the set CI
# checks out, and a walk of Packages/ descends into `.build`, where generated sources live.
entity_sources() {
    git ls-files -- "$ENTITY_DIR/*.swift"
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

# Every CD_ field of every CD_ record type in an export, as `record type<TAB>field<TAB>spelling`.
#
# CD_entityName IS COREDATA'S OWN AND IS NOT DECLARED ANYWHERE, which is why this comparison only
# ever runs one way: declared-and-absent is the defect, deployed-and-undeclared is the framework.
#
# THE SPELLING IS CARRIED because a field of the wrong type fails exactly as a missing one does, one
# export later — the sentence --complete's own safety argument rests on. Comparing names alone would
# say nothing about it, and an import that guessed a spelling wrongly would report green for good.
exported_fields() {
    awk '
        /RECORD TYPE CD_[A-Za-z0-9_]+/ { type = $3; next }
        /^[[:space:]]*CD_[A-Za-z0-9_]+[[:space:]]/ {
            spell = ""
            for (i = 2; i <= NF; i++) spell = spell (i > 2 ? " " : "") $i
            sub(/,$/, "", spell)
            printf "%s\t%s\t%s\n", type, $1, spell
        }
    ' "$1" | sort -u
}

# The snapshot with every missing field added, ready for `cktool import-schema --environment
# development`. Inserted directly after each record type's opening line rather than in sorted
# position: a CloudKit export comes back alphabetised whatever order it went in, so sorting here
# would only make this harder to read.
#
# THE FIELD LIST ARRIVES AS A FILE, NOT AS `-v`. BSD awk reads a `-v` assignment through its escape
# processing and rejects the embedded newline outright — "awk: newline in string" — leaving an empty
# output file that then fails validation for having no DEFINE SCHEMA in it, which reads like a bad
# schema rather than a bad call.
complete_schema() {
    local missing="$1" source="$2" out="$3"
    awk -F'\t' '
        NR == FNR {
            if ($0 != "") add[$1] = add[$1] sprintf("        %s %s,\n", $2, $3)
            next
        }
        {
            print
            if (match($0, /RECORD TYPE CD_[A-Za-z0-9_]+/)) {
                type = substr($0, RSTART, RLENGTH)
                sub(/^RECORD TYPE /, "", type)
                if (type in add) printf "%s", add[type]
            }
        }
    ' "$missing" "$source" >"$out"
}

failures=0
fail() { printf '  FAIL  %-22s %s\n' "$1" "$2" >&2; failures=$((failures + 1)); }
ok() { printf '  ok    %-22s %s\n' "$1" "$2"; }

# Check 3, over whichever export it is handed. `$1` is a .ckdb, `$2` names it in the report.
#
# IT IS THE ONE CHECK THAT RUNS OFF-NETWORK, because it is the one whose input can be committed.
check_fields() {
    local schema="$1" label="$2"
    shift 2
    local declared exported unreadable missing mistyped
    if (( $# == 0 )); then
        set -- $(entity_sources)
    fi
    declared="$(declared_fields "$@")"

    if [[ -z "$declared" ]]; then
        fail "field coverage" "found no @Model property under $ENTITY_DIR — the parse is broken."
        return 1
    fi

    # Both residues, reported together: a type with no spelling, and a declaration the parse could
    # not read at all. Neither can be skipped — see declared_fields()'s own note.
    unreadable="$(awk -F'\t' '
        $3 ~ /^UNMAPPED:/ { printf "%s.%s is %s, which has no CloudKit spelling here\n", $1, $2, substr($3, 10) }
        $3 ~ /^UNPARSED:/ { printf "%s: %s\n", $1, substr($3, 10) }
    ' <<<"$declared")"
    if [[ -n "$unreadable" ]]; then
        fail "field coverage" "declarations this check cannot turn into a field:"
        sed 's/^/        /' <<<"$unreadable" >&2
        cat >&2 <<'UNREADABLE'
        A type with no spelling: add it to declared_fields(), copied from a column of the same
        Swift type in an export. A declaration that could not be read: give it an explicit type
        annotation, which is what every column in SchemaV1 has. Until then nothing can be said
        about these fields, and a silent skip here is the defect this gate exists to catch.
UNREADABLE
        return 1
    fi

    exported="$(exported_fields "$schema")"
    missing="$(comm -23 \
        <(cut -f1,2 <<<"$declared") \
        <(cut -f1,2 <<<"$exported"))"

    if [[ -n "$missing" ]]; then
        fail "field coverage" "@Model properties with no field in $label:"
        sed 's/^/        /' <<<"$missing" >&2
        cat >&2 <<MISSING

        CoreData creates a field on the first export of a row holding a non-nil value for it, so
        these are the columns nothing has written yet — and Production is deploy-only, so the first
        row that DOES write one cannot create it. The mirroring delegate traps, never initialises,
        and that install stops importing and exporting for good.

            1  scripts/check-cloudkit-schema.sh --complete /tmp/complete.ckdb
            2  xcrun cktool import-schema --team-id TEAM --container-id CONTAINER \\
                   --environment development --file /tmp/complete.ckdb
            3  deploy Development -> Production in the Console
            4  scripts/check-cloudkit-schema.sh --refresh

MISSING
        return 1
    fi

    # The field is there; is it the column the model will try to write? Matched in awk rather than
    # with `join`, which would need both sides sorted the same way and has no opinion to offer here.
    mistyped="$(awk -F'\t' '
        NR == FNR { deployed[$1 "\t" $2] = $3; next }
        ($1 "\t" $2) in deployed && deployed[$1 "\t" $2] != $3 {
            printf "%s.%s  declared %s  deployed %s\n", $1, $2, $3, deployed[$1 "\t" $2]
        }
    ' <(printf '%s\n' "$exported") <(printf '%s\n' "$declared"))"

    if [[ -n "$mistyped" ]]; then
        fail "field coverage" "fields deployed as a different type in $label:"
        sed 's/^/        /' <<<"$mistyped" >&2
        cat >&2 <<'MISTYPED'

        A field of the wrong type fails on export exactly as a missing one does, and Production is
        deploy-only, so the client cannot correct it. Either the spelling in declared_fields() is
        wrong for that Swift type — check it against a column of the same type in the export — or
        the field was imported from a schema that guessed, and the container needs the field
        renamed and re-added in the Console. A CloudKit field's type cannot be changed in place.

MISTYPED
        return 1
    fi

    ok "field coverage" \
        "all $(wc -l <<<"$declared" | tr -d ' ') @Model properties have a field of the declared type in $label"
}

# --self-test: check 3 in both directions, over a scratch tree. `find` rather than `git ls-files`,
# for `check-cloudkit.sh`'s reason — a scratch tree is not a git checkout, and what is being
# exercised is the matching rather than the population.
#
# THE PASSING CASE IS FIRST, so a check that fired on everything is caught. The 23-field failure
# this script was written for is not a substitute for it: a gate is only evidence while it is known
# to have a green.
if [[ "$mode" == "self-test" ]]; then
    scratch="$(mktemp -d)"
    trap 'rm -rf "$scratch"' EXIT
    mkdir -p "$scratch/entities" "$scratch/empty"

    # EVERY DECLARATION SHAPE THE PARSE CLASSIFIES, in one fixture: two plain stored properties, a
    # `private(set)` one, one behind an attribute, and then the three that are deliberately NOT
    # columns — @Transient, computed, static. The passing case below is what asserts all three are
    # skipped, since the schema beside it carries no field for any of them.
    cat >"$scratch/entities/Alpha.swift" <<'EOF'
@Model
final class AlphaEntity: StoredEntity {
    var id: UUID = UUID()
    var deletedAt: Date?
    private(set) var tags: [String] = []
    @Attribute(.externalStorage) var blob: Data = Data()
    @Transient var scratch: Int = 0
    var derived: Int { count * 2 }
    static var fallback: Int { 0 }
    /// A doc comment naming `var decoy: Int` in prose, which must not be parsed as a property.
    var count: Int = 0
}

extension AlphaEntity {
    static var notDeleted: Predicate<AlphaEntity> { fatalError() }
}
EOF
    cat >"$scratch/complete.ckdb" <<'EOF'
DEFINE SCHEMA

    RECORD TYPE CD_AlphaEntity (
        CD_blob       BYTES QUERYABLE SORTABLE,
        CD_count      INT64 QUERYABLE SORTABLE,
        CD_deletedAt  TIMESTAMP QUERYABLE SORTABLE,
        CD_entityName STRING QUERYABLE SEARCHABLE SORTABLE,
        CD_id         STRING QUERYABLE SEARCHABLE SORTABLE,
        CD_tags       BYTES QUERYABLE SORTABLE,
        "___recordID" REFERENCE,
        GRANT READ TO "_world"
    );
EOF
    # The exact shape this task was written for: the optional column nothing has ever written.
    grep -v 'CD_deletedAt' "$scratch/complete.ckdb" >"$scratch/lazy.ckdb"
    # The same shape for a property declared behind an attribute — the column is ordinary, and the
    # first version of this parse dropped the declaration without a word.
    grep -v 'CD_blob' "$scratch/complete.ckdb" >"$scratch/no-blob.ckdb"
    # A field that IS there and is the wrong column: it fails on export exactly as a missing one.
    sed 's/CD_count      INT64 QUERYABLE SORTABLE/CD_count      STRING QUERYABLE SEARCHABLE SORTABLE/' \
        "$scratch/complete.ckdb" >"$scratch/mistyped.ckdb"
    sed 's/var count: Int = 0/var count: Decimal = 0/' "$scratch/entities/Alpha.swift" \
        >"$scratch/unmapped.swift"
    # NOTHING IN THIS REPO REQUIRES AN ANNOTATION, so this is a legal mirrored column — and the
    # shape that left the gate reporting green over a field it had never heard of.
    sed 's/var count: Int = 0/var count = 0/' "$scratch/entities/Alpha.swift" \
        >"$scratch/inferred.swift"

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

    echo "self-test — check 3, in both directions"
    expect "field coverage" 0 check_fields "$scratch/complete.ckdb" fixture "$scratch/entities/Alpha.swift"
    expect "…a lazily-created column" 1 check_fields "$scratch/lazy.ckdb" fixture "$scratch/entities/Alpha.swift"
    expect "…a column behind an attribute" 1 check_fields "$scratch/no-blob.ckdb" fixture "$scratch/entities/Alpha.swift"
    expect "…a field of the wrong type" 1 check_fields "$scratch/mistyped.ckdb" fixture "$scratch/entities/Alpha.swift"
    expect "…an unmapped Swift type" 1 check_fields "$scratch/complete.ckdb" fixture "$scratch/unmapped.swift"
    expect "…a property with no annotation" 1 check_fields "$scratch/complete.ckdb" fixture "$scratch/inferred.swift"
    # A parse that finds nothing must fail rather than agree with an empty schema — the same
    # green-while-enforcing-nothing failure check 2's own emptiness guard exists to prevent.
    expect "…an empty parse" 1 check_fields "$scratch/complete.ckdb" fixture "$scratch/empty"

    echo
    if (( failures > 0 )); then
        echo "$failures self-test case(s) failed — this gate does not do what its header claims." >&2
        exit 1
    fi
    echo "check 3 fires on a missing field, a mistyped one, an unmapped type and a declaration it"
    echo "cannot read — and not on a complete schema whose non-columns it correctly skips."
    exit 0
fi

# --offline and --complete read the committed snapshot and stop there. No token, no network, and
# no claim about the container beyond what the snapshot says — which is check 5's whole job.
if [[ "$mode" == "offline" || "$mode" == "complete" ]]; then
    if [[ ! -f "$SNAPSHOT" ]]; then
        echo "check-cloudkit-schema.sh: $SNAPSHOT is missing." >&2
        echo "  It is the deployed schema, committed. Re-record it with --refresh." >&2
        exit 66
    fi

    if [[ "$mode" == "complete" ]]; then
        declared="$(declared_fields $(entity_sources))"
        if grep -qE '(UNMAPPED|UNPARSED):' <<<"$declared"; then
            check_fields "$SNAPSHOT" "the snapshot" || true
            exit 1
        fi
        # The declared rows the snapshot has no field for, keeping the spelling column — which is
        # the one `comm` would throw away, and the one the import needs.
        missing="$(awk -F'\t' 'NR == FNR { have[$1 "\t" $2] = 1; next } !(($1 "\t" $2) in have)' \
            <(exported_fields "$SNAPSHOT") <(printf '%s\n' "$declared"))"
        if [[ -z "$missing" ]]; then
            echo "every @Model property already has a field in $SNAPSHOT — nothing to import."
            exit 0
        fi
        list="$(mktemp)"
        trap 'rm -f "$list"' EXIT
        printf '%s\n' "$missing" >"$list"
        complete_schema "$list" "$SNAPSHOT" "$complete_out"
        echo "wrote $complete_out — $(wc -l <<<"$missing" | tr -d ' ') field(s) added:"
        awk -F'\t' '{ printf "  %s.%s  %s\n", $1, $2, $3 }' <<<"$missing"
        echo
        echo "  validate it before importing, which costs nothing and is not the same call:"
        echo "      xcrun cktool validate-schema --team-id TEAM --container-id CONTAINER \\"
        echo "          --environment development --file $complete_out"
        exit 0
    fi

    echo "CloudKit schema, offline: every @Model property against $SNAPSHOT (TR-1.7)"
    check_fields "$SNAPSHOT" "the snapshot" || true
    echo
    if (( failures > 0 )); then
        echo "$failures CloudKit schema check(s) failed." >&2
        exit 1
    fi
    echo "the snapshot covers the model. It is only evidence about the container while the"
    echo "networked run agrees — scripts/check-cloudkit-schema.sh, after any deployment."
    exit 0
fi

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

  Only the networked modes need it. The chain gate does not:

      scripts/check-cloudkit-schema.sh --offline

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

# --refresh re-records the snapshot and says nothing else. It is deliberately NOT part of a passing
# run: a check that repaired its own expectation would agree with every deployment, including the
# one that never happened.
if [[ "$mode" == "refresh" ]]; then
    export_schema development "$scratch/development.ckdb" || exit 1
    export_schema production "$scratch/production.ckdb" || exit 1
    if ! diff -q "$scratch/development.ckdb" "$scratch/production.ckdb" >/dev/null; then
        echo "check-cloudkit-schema.sh: development and production disagree — deploy first." >&2
        echo "  The snapshot records what is DEPLOYED; recording an undeployed schema would make" >&2
        echo "  the offline gate pass over exactly the state it exists to catch." >&2
        exit 1
    fi
    mkdir -p "$(dirname "$SNAPSHOT")"
    cp "$scratch/development.ckdb" "$SNAPSHOT"
    echo "re-recorded $SNAPSHOT from $container (team $team), both environments agreeing."
    echo "commit it with the change that deployed it."
    exit 0
fi

echo "CloudKit schema: $container (team $team)"

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

# THE DECLARED SIDE NEEDS ITS OWN EMPTINESS GUARD, because the `|| true` above makes a parse that
# matched nothing indistinguishable from a tree with no @Model in it. `$present` is answered by the
# check just above; `$declared` was not, so a broken parse fell through every branch below to
# "all @Model types present" — check 2 reporting ok while doing nothing, over the count `wc -l`
# gives an empty string, which is 1. `check-cloudkit.sh` guards the same parse the same way. What
# makes a wrong ok expensive here rather than merely wrong: Production is additive, so a partial
# schema promoted on a green run cannot be taken back.
if [[ -z "$declared" ]]; then
    fail "entity coverage" "found no @Model under $ENTITY_DIR — the parse is broken, not the tree."
    echo "        Nothing can be said about entity coverage until it is, and deploying on this" >&2
    echo "        run would promote whatever Development happens to hold. The parse is the one" >&2
    echo "        check-cloudkit.sh uses for DOD-0.4; fix it in both." >&2
    exit 1
fi

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

check_fields "$scratch/development.ckdb" "development" || true

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

# Check 5. The snapshot is what --offline reads, so a stale one is a gate reporting on a container
# that stopped existing in that shape.
if [[ ! -f "$SNAPSHOT" ]]; then
    fail "snapshot is current" "$SNAPSHOT is missing — re-record it with --refresh."
elif diff -u "$SNAPSHOT" "$scratch/production.ckdb" >"$scratch/snapshot-diff"; then
    ok "snapshot is current" "$SNAPSHOT is the deployed schema"
else
    fail "snapshot is current" "$SNAPSHOT is not what is deployed:"
    sed 's/^/        /' "$scratch/snapshot-diff" >&2
    echo "        Re-record it with --refresh and commit it with the change that deployed it." >&2
fi

echo
if (( failures > 0 )); then
    echo "$failures CloudKit schema check(s) failed." >&2
    exit 1
fi
echo "schema deployed and verified — record the date in docs/phase-1/tasks/T-1.70-*.md."
