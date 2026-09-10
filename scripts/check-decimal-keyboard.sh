#!/usr/bin/env bash
#
# G-3.4: locale-strict number entry cannot refuse from the keyboard this app actually ships.
#
#   scripts/check-decimal-keyboard.sh              # the gate
#   scripts/check-decimal-keyboard.sh --self-test  # prove each check fires, in both directions
#
# WHAT CLAIM THIS HOLDS UP, AND WHY IT IS A GATE RATHER THAN A SENTENCE. `LocalizedNumberField`
# refuses a string that is not, in whole, a number in the user's locale — `102.5` typed where the
# decimal is written as a comma is not one — and it says nothing when it refuses. T-1.80 narrowed
# that from a gap to a near-impossibility by measurement: every numeric field routes through
# `DesignSystem`'s `decimalKeyboard()` → `.decimalPad`, which offers no `.` key in a comma-decimal
# locale, so the refusing input cannot be typed. What is left is a hardware keyboard — iPad with a
# Magic Keyboard, a Mac, a paired Bluetooth one — and T-1.92 recorded the author's answer that no
# message is owed there.
#
# That answer is only as good as its premise, and the premise is the thing that decays. The field
# had four entry points when T-1.80 measured it and has five call sites over more hosts now, one of
# them (`SetEditorControls.numberField`) fanning out per set rather than per screen. A tenth host
# arriving with its own `.keyboardType(.numbersAndPunctuation)` would put a `.` key back under every
# lifter in a comma-decimal locale and make the recorded decision silently wrong — in a diff about
# something else, with nothing in the toolchain reading it. Same shape as
# check-exempt-encryption.sh, which guards a legal declaration for the same reason.
#
#   1  bypass      No source sets `keyboardType` directly. `decimalKeyboard()` is the only route,
#                  which is what makes checks 2 and 3 exhaustive rather than indicative — a host
#                  that types its own field is invisible to both.
#   2  inventory   The set of files calling `decimalKeyboard()` is EXACTLY the recorded one. An
#                  exact set rather than a floor, deliberately: snapshot-tests.sh's per-suite floor
#                  is the cautionary case in this repo, where a number that only ever moves up
#                  drifted stale three suites at a time and passed throughout. A sixth host is a
#                  decision someone confirms and records here, and a host that disappears is one
#                  whose screen stopped taking numbers.
#   3  coverage    Every module that PARSES with `LocalizedNumberField` also calls
#                  `decimalKeyboard()`. This is the one that sees a whole new module entering
#                  numeric entry — check 2 would fail on it too, but as "unexpected host" rather
#                  than as "this module types numbers with no keyboard set", and the second is the
#                  diagnosis.
#
# Checks 2 and 3 do not subsume each other in the other direction either: 3 is module-granular and
# would pass a sixth field added inside Logging, which is exactly the per-set fan-out case, and 2
# catches that.
#
# THE POPULATION IS `git ls-files`, for check-no-third-party.sh's two reasons: it is the set CI
# checks out, and a directory walk descends into Packages/*/.build.
#
# WHEN THIS GATE IS SUPPOSED TO FAIL: a task adds or removes a numeric field. Update HOSTS in the
# same commit, and — if the new host does NOT route through `decimalKeyboard()` — reopen the
# author's answer rather than adding an exception, because the answer was given about a keyboard
# that cannot produce the refusal.

set -euo pipefail

cd "$(dirname "$0")/.."

SELF_TEST=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --self-test) SELF_TEST=1; shift ;;
        -h|--help)
            awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
            exit 0 ;;
        *) echo "check-decimal-keyboard.sh: unknown option '$1'" >&2; exit 64 ;;
    esac
done

# Every file that may call `decimalKeyboard()`, as of T-1.92. Sorted, because check 2 compares this
# against a sorted listing of the tree.
#
# The five are four screens plus one shared control: `SetEditorControls.numberField`, which the Log
# sheet's per-set fold draws once per set (`FR-17.9.4`) — so the host count and the field count have
# not been the same number since T-17.01, and this list is the former.
HOSTS=(
    "Packages/Features/ExerciseLibrary/Sources/ExerciseLibrary/TrainingMaxEditorView.swift"
    "Packages/Features/Logging/Sources/Logging/EquipmentProfileEditorView.swift"
    "Packages/Features/Logging/Sources/Logging/SetEditorFieldsView.swift"
    "Packages/Features/Routines/Sources/Routines/RoutineGroupRow.swift"
    "Packages/Features/Settings/Sources/Settings/BodyweightEntryFormView.swift"
)

# Where `decimalKeyboard()` is defined. It is the one file allowed to name `keyboardType`, and it is
# not a host.
DEFINITION="Packages/DesignSystem/Sources/DesignSystem/DecimalKeyboard.swift"

# The parsing direction only. `render(_:locale:)` writes a value back out and a module can call it
# with no field at all, so anchoring check 3 on the whole type would fail a module that only
# formats.
PARSE_RE='LocalizedNumberField\.(decimal|weight|count)\('

failures=0

fail() {
    printf '  FAIL  %-14s %s\n' "$1" "$2" >&2
    failures=$((failures + 1))
}

ok() { printf '  ok    %-14s %s\n' "$1" "$2"; }

# Drops whole-line comments, so this script's own header, `DecimalKeyboard.swift`'s doc comment and
# `SetEditorControls`'s note about drift cannot fire any check. A trailing comment on a real line
# still fires. Same filter as check-no-third-party.sh's, kept local for the same reason.
code_only() {
    awk '{ body = $0; sub(/^[^:]*:[0-9]+:/, "", body); if (body !~ /^[ \t]*(\/\/|\*|\/\*|#)/) print }'
}

# Files under `paths` containing `re` in code — one path per line, sorted and unique.
files_matching() {
    local re="$1"
    shift
    (( $# == 0 )) && return 0
    grep -nHE "$re" "$@" 2>/dev/null | code_only | cut -d: -f1 | sort -u
}

# The module a source file belongs to — `Packages/Features/Logging`, `Packages/DesignSystem`.
module_of() { sed -E 's#(Packages/(Features/)?[^/]+)/Sources/.*#\1#' <<<"$1"; }

check_bypass() {
    local hits
    hits="$(files_matching '\.keyboardType\(' "$@" | grep -v "^${DEFINITION}\$" || true)"
    if [[ -n "$hits" ]]; then
        fail "bypass" "G-3.4: a source sets keyboardType directly instead of decimalKeyboard(). Found:"
        sed 's/^/          /' <<<"$hits" >&2
        return 1
    fi
    return 0
}

check_inventory() {
    local found expected diff
    found="$(files_matching 'decimalKeyboard\(\)' "$@" | grep -v "^${DEFINITION}\$" || true)"
    expected="$(printf '%s\n' "${HOSTS[@]}" | sort)"
    diff="$(comm -3 <(printf '%s\n' "$found") <(printf '%s\n' "$expected") || true)"
    if [[ -n "$diff" ]]; then
        fail "inventory" "G-3.4: the decimalKeyboard() hosts are not the recorded set."
        echo "          left column = in the tree but not in HOSTS; right = recorded but gone:" >&2
        sed 's/^/          /' <<<"$diff" >&2
        return 1
    fi
    return 0
}

check_coverage() {
    local parsing keyboards module missing=""
    parsing="$(files_matching "$PARSE_RE" "$@")"
    keyboards="$(files_matching 'decimalKeyboard\(\)' "$@" | grep -v "^${DEFINITION}\$" || true)"
    local typed
    typed="$(while IFS= read -r f; do [[ -n "$f" ]] && module_of "$f"; done <<<"$keyboards" | sort -u)"
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        module="$(module_of "$f")"
        grep -qx "$module" <<<"$typed" || missing+="$module (parses in $f)"$'\n'
    done <<<"$parsing"
    missing="$(sort -u <<<"$missing" | sed '/^$/d')"
    if [[ -n "$missing" ]]; then
        fail "coverage" "G-3.4: a module parses numbers but sets no decimal keyboard. Found:"
        sed 's/^/          /' <<<"$missing" >&2
        return 1
    fi
    return 0
}

collect() {
    FILES=()
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] && FILES+=("$line")
    done <<<"${1:-}"
}

# Runs one check over its population, failing when that population is empty — the
# green-while-enforcing-nothing shape, as in check-no-third-party.sh.
gate() {
    local label="$1" summary="$2" checker="$3"
    shift 3
    if (( $# == 0 )); then
        fail "$label" "no file matched the pathspec — the population is wrong."
        return 0
    fi
    if "$checker" "$@"; then ok "$label" "$# $summary"; fi
    return 0
}

if (( SELF_TEST )); then
    scratch="$(mktemp -d)"
    trap 'rm -rf "$scratch"' EXIT

    # The fixtures mirror the real tree's shape, because two of the three checks derive a module
    # from a path and would be meaningless over flat files.
    host_dir="$scratch/Packages/Features/Settings/Sources/Settings"
    other_dir="$scratch/Packages/Features/Dashboard/Sources/Dashboard"
    mkdir -p "$host_dir" "$other_dir"

    cat >"$host_dir/BodyweightEntryFormView.swift" <<'EOF'
TextField(text: $draft.weightText) { Text("Weight") }
    .decimalKeyboard()
EOF
    cat >"$host_dir/BodyweightEntryDraft.swift" <<'EOF'
var weight: Weight? { LocalizedNumberField.weight(weightText, in: unit, locale: locale) }
EOF
    # The bypass, and the reason check 1 exists: a field typed by hand, which puts a `.` key back.
    cat >"$other_dir/Bypass.swift" <<'EOF'
TextField(text: $text) { Text("Weight") }
    .keyboardType(.numbersAndPunctuation)
EOF
    # Prose naming the banned spelling — what this script's own header does, and what
    # DecimalKeyboard.swift's doc comment does.
    cat >"$other_dir/Prose.swift" <<'EOF'
/// **A modifier rather than an `#if` at every call site.** `keyboardType(_:)` does not exist on
// macOS, so never write .keyboardType(.decimalPad) at a call site.
EOF
    # A module that parses and sets no keyboard — check 3's case, and the one check 2 diagnoses
    # only as "unexpected host".
    cat >"$other_dir/Untyped.swift" <<'EOF'
var reps: Int? { LocalizedNumberField.count(repsText, locale: locale) }
EOF
    # A module that only formats. It must NOT be required to set a keyboard.
    cat >"$other_dir/FormatsOnly.swift" <<'EOF'
Text(LocalizedNumberField.render(value, locale: locale))
EOF
    # A sixth host, correctly routed and simply not recorded. This is check 2's whole point and it
    # is NOT the bypass fixture: a host that types its own field never calls `decimalKeyboard()` at
    # all, so it is invisible to the inventory and is check 1's to catch. The self-test's first
    # version used the bypass file here and passed the case by accident.
    cat >"$other_dir/UnrecordedHost.swift" <<'EOF'
TextField(text: $draft.repsText) { Text("Reps") }
    .decimalKeyboard()
EOF

    # `HOSTS` and `DEFINITION` are absolute in the real run and scratch-relative here.
    real_hosts=("${HOSTS[@]}")
    real_definition="$DEFINITION"
    HOSTS=("$host_dir/BodyweightEntryFormView.swift")
    DEFINITION="$scratch/none"
    # `module_of` strips the scratch prefix's Packages/... shape, which the fixtures reproduce.
    module_of() { sed -E "s#^.*(Packages/(Features/)?[^/]+)/Sources/.*#\1#" <<<"$1"; }

    expect() {
        local label="$1" want="$2"; shift 2
        local before=$failures
        "$@" >/dev/null 2>&1 || true
        local fired=$(( failures > before ))
        failures=$before
        if [[ "$fired" == "$want" ]]; then
            printf '  ok    %-38s %s\n' "$label" "$([[ $want == 1 ]] && echo fires || echo passes)"
        else
            printf '  FAIL  %-38s expected fired=%s, got %s\n' "$label" "$want" "$fired" >&2
            failures=$((failures + 1))
        fi
    }

    echo "self-test — each check, in both directions"

    collect "$other_dir/Bypass.swift"
    expect "bypass" 1 check_bypass "${FILES[@]}"
    collect "$host_dir/BodyweightEntryFormView.swift"
    expect "…decimalKeyboard() only" 0 check_bypass "${FILES[@]}"
    collect "$other_dir/Prose.swift"
    expect "…named in a comment" 0 check_bypass "${FILES[@]}"

    collect "$host_dir/BodyweightEntryFormView.swift"
    expect "inventory" 0 check_inventory "${FILES[@]}"
    collect "$(printf '%s\n%s\n' "$host_dir/BodyweightEntryFormView.swift" "$other_dir/UnrecordedHost.swift")"
    expect "…an unrecorded host appears" 1 check_inventory "${FILES[@]}"
    # The host recorded but gone — the direction a floor cannot see at all.
    HOSTS=("$host_dir/BodyweightEntryFormView.swift" "$host_dir/Vanished.swift")
    collect "$host_dir/BodyweightEntryFormView.swift"
    expect "…a recorded host disappears" 1 check_inventory "${FILES[@]}"
    HOSTS=("$host_dir/BodyweightEntryFormView.swift")

    collect "$(printf '%s\n%s\n' "$host_dir/BodyweightEntryFormView.swift" "$host_dir/BodyweightEntryDraft.swift")"
    expect "coverage" 0 check_coverage "${FILES[@]}"
    collect "$(printf '%s\n%s\n' "$host_dir/BodyweightEntryFormView.swift" "$other_dir/Untyped.swift")"
    expect "…a module parses with no keyboard" 1 check_coverage "${FILES[@]}"
    collect "$(printf '%s\n%s\n' "$host_dir/BodyweightEntryFormView.swift" "$other_dir/FormatsOnly.swift")"
    expect "…a module that only formats" 0 check_coverage "${FILES[@]}"

    expect "an empty population" 1 gate "bypass" "file(s)" check_bypass

    HOSTS=("${real_hosts[@]}")
    DEFINITION="$real_definition"

    echo
    if (( failures > 0 )); then
        echo "$failures self-test case(s) failed — this gate does not do what its header claims." >&2
        exit 1
    fi
    echo "all three checks fire, and none fires on a clean tree."
    exit 0
fi

echo "decimal keyboard: every numeric field is typed on a pad with no decimal point (G-3.4)"

collect "$(git ls-files -- 'Packages/*/Sources/*.swift' 'Attempt/*.swift')"
gate "bypass" "source file(s), decimalKeyboard() the only route" check_bypass ${FILES[@]+"${FILES[@]}"}
gate "inventory" "source file(s), ${#HOSTS[@]} recorded host(s)" check_inventory ${FILES[@]+"${FILES[@]}"}
gate "coverage" "source file(s), every parsing module typed" check_coverage ${FILES[@]+"${FILES[@]}"}

echo
if (( failures > 0 )); then
    echo "$failures decimal-keyboard check(s) failed." >&2
    echo "T-1.92 recorded the author's answer that a hardware-keyboard user is owed no message," >&2
    echo "on the premise this gate holds up. A new host that does not route through" >&2
    echo "decimalKeyboard() reopens that answer — see this script's header." >&2
    exit 1
fi
