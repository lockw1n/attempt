#!/usr/bin/env bash
#
# NFR-0.1: the PowerliftingCore test suite must run in under 5 seconds.
#
#   scripts/check-suite-runtime.sh                # the gate: run the suite, parse the total, compare
#   scripts/check-suite-runtime.sh --max 2        # tighter, for a local experiment
#   scripts/check-suite-runtime.sh --from FILE    # parse a recorded run instead of running one
#   scripts/check-suite-runtime.sh --self-test    # prove the gate fires, in both directions
#
# THIS IS AN ARCHITECTURAL TRIPWIRE, NOT A PERFORMANCE GATE. Read that before optimising anything
# in response to it. The suite is ~460 pure value-type tests with no I/O, no fixtures and no async,
# and it runs in about 0.05 s — roughly 100x under this budget. Domain code will not close that gap
# by growing; the arithmetic says so. What closes it is a URLSession, a Thread.sleep, a polling
# loop, or a persistence container arriving in a test fixture — and none of those cost tenths of a
# second, they cost whole ones. So a failure here almost certainly means something entered
# PowerliftingCore that does not belong in it, and the fix is to move that thing out, not to make
# the tests faster.
#
# WHY THE BUDGET IS 5 AND NOT SOMETHING NEAR THE CURRENT READING. Two reasons, and the second is
# the load-bearing one. 5 is what NFR-0.1 says, and no tighter figure has a requirement behind it.
# But a tight budget would also be worse at the job described above: the reading varies by ~15% run
# to run on an idle machine, and a loaded CI runner or a cold scratch directory moves it further.
# A budget set near the noise floor fails for reasons that have nothing to do with the boundary it
# guards, which turns a tripwire into a flaky test. 5 s sits deliberately far above value-type
# noise and far below what a single I/O-doing test costs.
#
# The comparison is STRICT — NFR-0.1 says "under 5 seconds", so a reading of exactly the budget
# fails. Pinned by the boundary case in --self-test.
#
# WHAT THE GATE PARSES, AND WHY IT IS FUSSY ABOUT IT. `swift test` ends with one line of the form
#
#     Test run with 462 tests in 89 suites passed after 0.051 seconds.
#
# and the merged output also carries ~550 per-test and per-suite lines of the shape "passed after
# N seconds", so the anchor has to be "Test run with". Which stream that final line lands on is not
# documented and was observed to depend on whether the destination is a pipe or a file, so the run
# is captured merged and the parser requires EXACTLY ONE match. Not the first match: a format change
# that emitted two totals would survive `head -1` silently while reporting a number nobody chose.
# Four conditions are failures, all of them loudly: no total line, more than one, a suite that
# reported failure, and a non-zero exit from `swift test` itself. An absent number must never
# compare favourably against the budget.
#
# SCOPE — do not widen either of these without a requirement to point at:
#
#   Not on Linux.     The Linux job exists to catch Apple API in the core and deliberately carries
#                     nothing that can redden it for another reason. A second measurement of record
#                     on a different toolchain and a container CPU is exactly that.
#   Not globbed.      Every other script here discovers packages by glob, on purpose. This one names
#                     PowerliftingCore, because NFR-0.1 names PowerliftingCore. A persistence suite
#                     backed by a real store will be orders of magnitude slower and that is correct
#                     behaviour, not a regression — globbing this gate would make it a false alarm
#                     on the day that suite lands.
#
# Runs in the `test` job after the packages are already built, so it measures execution rather than
# compilation. Uses the same strict flags as every other build path, which is what keeps the
# scratch directory warm rather than triggering a rebuild.

set -euo pipefail

# Hardening, NOT a fix for a demonstrated bug — said plainly because the difference matters. The
# gate turns on a decimal comparison, so LC_NUMERIC is a plausible way for "0.051" to be read as
# zero and compare favourably against the budget forever. It was tested under de_DE and fr_FR and
# awk's *parse* was correct in every one; only its output formatting changed. No case was found
# where this line changes an outcome. It is kept because it is free and removes a class of
# reasoning that would otherwise be redone every time this comparison is touched.
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PACKAGE="Packages/PowerliftingCore"
MAX="${SUITE_RUNTIME_MAX:-5}"
FROM=""
SELF_TEST=0

# Anchored on "Test run with" — the ~550 per-test lines share the "passed after N seconds" suffix.
# `tests?`/`suites?` because the wording singularises, which a one-test package would hit.
TOTAL_RE='Test run with ([0-9]+) tests? in ([0-9]+) suites? (passed|failed) after ([0-9]+(\.[0-9]+)?) seconds'

usage() {
    # The header block above, minus the shebang, up to the first blank/non-comment line.
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

need_value() {
    [[ $# -ge 2 ]] || { echo "check-suite-runtime.sh: $1 needs a value" >&2; exit 64; }
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --max)       need_value "$@"; MAX="$2"; shift 2 ;;
        --from)      need_value "$@"; FROM="$2"; shift 2 ;;
        --self-test) SELF_TEST=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *) echo "check-suite-runtime.sh: unknown argument '$1'" >&2; exit 64 ;;
    esac
done

# A NON-NUMERIC BUDGET IS REJECTED HERE, and this is the one place in the script where getting it
# wrong fails OPEN rather than closed. awk compares two operands as strings unless both look
# numeric, so a budget of "abc" made `900.0 >= "abc"` false — "9" sorts below "a" — and a
# 900-second suite exited 0 reporting PASS. Every other failure mode in this file errs towards
# red; that one errs towards green, which is the only kind that goes unnoticed.
#
# Guarded twice on purpose: validated here, and the comparison itself forces numeric context. The
# validation gives the good error message; the coercion is what holds if a future edit routes a
# budget around this check.
if ! [[ "$MAX" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "check-suite-runtime.sh: budget must be a number of seconds, got '$MAX'" >&2
    echo "      Set it with --max or \$SUITE_RUNTIME_MAX. NFR-0.1's figure is 5." >&2
    exit 64
fi

cd "$REPO_ROOT"

# Parse one captured run and gate on it. Prints the reading on success; on failure says which of
# the four conditions tripped, because they call for different fixes.
#
#   $1  path to the captured output
#   $2  budget in seconds
#
# Returns 0 when the run is under budget, 1 otherwise.
check_output() {
    local out="$1" max="$2"
    local matches line tests suites verdict duration

    # Extract FIRST, then count what was extracted. Counting with `grep -c` instead would count
    # matching *lines* while the extraction below yields *matches*, and the two differ the moment
    # two totals share a line — at which point the ambiguity check passes on a count of 1 while the
    # extractions are silently multi-valued, which is the exact failure this check exists to stop.
    # Doing it in this order makes the invariant true by construction rather than by luck.
    line="$(grep -oE "$TOTAL_RE" "$out" || true)"

    if [[ -z "$line" ]]; then
        matches=0
    else
        matches="$(printf '%s\n' "$line" | wc -l | tr -d ' ')"
    fi

    if [[ "$matches" -eq 0 ]]; then
        echo "FAIL  no test-run total found in the output." >&2
        echo "      Expected one line of the form:" >&2
        echo "        Test run with N tests in M suites passed after D seconds." >&2
        echo "      Either \`swift test\` did not get as far as running, or its output format" >&2
        echo "      changed. This is a failure and not a pass on purpose: a parser that has" >&2
        echo "      silently stopped matching looks exactly like a suite that is comfortably" >&2
        echo "      under budget. Fix the pattern in TOTAL_RE, then re-run --self-test." >&2
        return 1
    fi

    if [[ "$matches" -gt 1 ]]; then
        echo "FAIL  found $matches test-run totals, expected exactly 1 — the reading is ambiguous." >&2
        echo "      Taking the first would report a number nobody chose. If this script was" >&2
        echo "      pointed at more than one package, do not do that: NFR-0.1 is about" >&2
        echo "      PowerliftingCore, and the header says why this gate is not globbed." >&2
        return 1
    fi

    # The exactly-one check above is what makes these four extractions single-valued. Without it
    # they silently become multi-line and every consumer degrades differently: awk takes the
    # leading number, the verdict comparison fails against a two-line string. That is not a
    # theoretical worry — it is what a mutation probe of this function actually did.
    # shellcheck disable=SC2001  # a sed extraction reads better here than nested parameter expansion
    tests="$(sed -E "s/$TOTAL_RE/\1/" <<<"$line")"
    suites="$(sed -E "s/$TOTAL_RE/\2/" <<<"$line")"
    verdict="$(sed -E "s/$TOTAL_RE/\3/" <<<"$line")"
    duration="$(sed -E "s/$TOTAL_RE/\4/" <<<"$line")"

    if [[ "$verdict" != "passed" ]]; then
        echo "FAIL  the suite did not pass, so its duration means nothing." >&2
        echo "      $line" >&2
        echo "      Fix the failing tests; this gate has nothing to say until they pass." >&2
        return 1
    fi

    # Strict: NFR-0.1 says "under 5 seconds", so exactly the budget is a failure.
    # `+0` forces numeric context on both sides. Without it awk string-compares whenever an operand
    # does not look numeric, and a string comparison of a duration against a budget can land either
    # way — see the note beside the budget validation above.
    if awk -v d="$duration" -v m="$max" 'BEGIN { exit !(d + 0 >= m + 0) }'; then
        printf 'PowerliftingCore  %s tests in %s suites  %s s  (budget %s s, NFR-0.1)  FAIL\n' \
            "$tests" "$suites" "$duration" "$max"
        {
            echo
            echo "The core suite is no longer under its NFR-0.1 budget."
            echo
            echo "Before optimising a test, check what was added. This module is pure value types"
            echo "with no I/O, and it ran ~100x under budget across the whole of Phase 0 — a jump"
            echo "to seconds is what a network call, a sleep, a polling loop or a persistence"
            echo "container in a fixture looks like, not what more tests look like. If one of those"
            echo "has arrived in PowerliftingCore, the boundary is the bug and NFR-0.2 probably has"
            echo "something to say about it too."
        } >&2
        return 1
    fi

    printf 'PowerliftingCore  %s tests in %s suites  %s s  (budget %s s, NFR-0.1)  PASS\n' \
        "$tests" "$suites" "$duration" "$max"
    return 0
}

# --self-test: seven canned runs through check_output, six of which must fail. The positive case is
# not padding — a script that rejected everything would satisfy "has been seen to fire" while
# gating nothing, which is the failure mode verify-lint-rules.sh exists to catch.
#
# Each negative case asserts WHICH failure fired, not merely that one did. Asserting the exit
# status alone lets any check stand in for any other, and that is not hypothetical: with the
# ambiguity check disabled, the two-total fixture still failed — via the verdict branch, because
# a two-line capture makes `verdict` the string "passed\npassed" — and reported "the suite did not
# pass" about a suite that had passed twice. The gate was green, the diagnosis was wrong, and a
# status-only assertion could not tell the difference.
if (( SELF_TEST )); then
    scratch="$(mktemp -d)"
    trap 'rm -rf "$scratch"' EXIT

    cat >"$scratch/pass.txt" <<'EOF'
✔ Suite "Weight" passed after 0.032 seconds.
✔ Test run with 462 tests in 89 suites passed after 0.051 seconds.
EOF
    cat >"$scratch/over.txt" <<'EOF'
✔ Test run with 462 tests in 89 suites passed after 7.500 seconds.
EOF
    cat >"$scratch/boundary.txt" <<'EOF'
✔ Test run with 462 tests in 89 suites passed after 5.000 seconds.
EOF
    cat >"$scratch/missing.txt" <<'EOF'
✔ Suite "Weight" passed after 0.032 seconds.
✔ Test "Every 250 g target through the band a lifter works in" passed after 0.032 seconds.
EOF
    cat >"$scratch/double.txt" <<'EOF'
✔ Test run with 462 tests in 89 suites passed after 0.051 seconds.
✔ Test run with 462 tests in 89 suites passed after 0.049 seconds.
EOF
    cat >"$scratch/nonnumeric.txt" <<'EOF'
✔ Test run with 462 tests in 89 suites passed after some seconds.
EOF
    # Two totals sharing ONE line. Separate from double.txt on purpose: a line-counting ambiguity
    # check passes this at a count of 1 and then extracts two of everything.
    cat >"$scratch/double-inline.txt" <<'EOF'
✔ Test run with 1 tests in 1 suites passed after 0.051 seconds. Test run with 2 tests in 2 suites passed after 9.900 seconds.
EOF
    cat >"$scratch/failed.txt" <<'EOF'
✘ Test run with 462 tests in 89 suites failed after 0.051 seconds.
EOF
    # The two either side of the default budget, for the end-to-end checks below.
    cat >"$scratch/just-under.txt" <<'EOF'
✔ Test run with 462 tests in 89 suites passed after 4.999 seconds.
EOF
    cat >"$scratch/just-over.txt" <<'EOF'
✔ Test run with 462 tests in 89 suites passed after 5.000 seconds.
EOF
    # A quarter of an hour. Nothing legitimate reaches this; it exists so the garbage-budget case
    # below cannot pass by being genuinely fast.
    cat >"$scratch/very-slow.txt" <<'EOF'
✔ Test run with 462 tests in 89 suites passed after 900.000 seconds.
EOF

    # fixture | budget | must pass? | expected output | what it pins
    cases=(
        "pass.txt|5|yes|PASS|a healthy run under budget is accepted"
        "over.txt|5|no|no longer under its NFR-0.1 budget|a run over budget is rejected"
        "boundary.txt|5|no|no longer under its NFR-0.1 budget|exactly the budget is rejected — NFR-0.1 says *under*"
        "missing.txt|5|no|no test-run total found|no total line fails, rather than comparing favourably"
        "double.txt|5|no|found 2 test-run totals|two totals fail *as ambiguous*, not via some other branch"
        "double-inline.txt|5|no|found 2 test-run totals|two totals on ONE line are ambiguous too — matches, not lines"
        "nonnumeric.txt|5|no|no test-run total found|an unparseable duration fails"
        "failed.txt|5|no|the suite did not pass|a failing suite fails, with its own message"
    )

    failures=0
    n=0
    total=$(( ${#cases[@]} + 4 ))   # +4 for the CLI-level checks after the loop

    for spec in "${cases[@]}"; do
        IFS='|' read -r fixture budget expect expected_output note <<<"$spec"
        n=$((n + 1))
        printf '%d/%d  %-14s %s\n' "$n" "$total" "$fixture" "$note"

        if output="$(check_output "$scratch/$fixture" "$budget" 2>&1)"; then
            actual="pass"
        else
            actual="fail"
        fi

        if [[ ( "$expect" == "yes" && "$actual" != "pass" ) || ( "$expect" == "no" && "$actual" != "fail" ) ]]; then
            echo "      FAIL  gate ${actual}ed; it must $([[ $expect == yes ]] && echo pass || echo fail)." >&2
            failures=$((failures + 1))
        elif ! grep -qF "$expected_output" <<<"$output"; then
            echo "      FAIL  gate ${actual}ed, but for the wrong reason." >&2
            echo "            expected to say: $expected_output" >&2
            echo "            actually said:   $(head -1 <<<"$output")" >&2
            failures=$((failures + 1))
        else
            echo "      ok    gate ${actual}ed, saying \"$expected_output\""
        fi
    done

    # The seven above all pass an explicit budget, so none of them can see the DEFAULT — and the
    # default is the only number NFR-0.1 actually specifies. Found by a mutation probe: changing
    # `SUITE_RUNTIME_MAX:-5` to 500 left the whole suite above green. These two go through the real
    # CLI with the variable unset, and they bracket 5 rather than merely sitting below it, so the
    # default is pinned to the requirement's figure and not just to "something roomy".
    # A garbage budget is in here rather than beside the parser cases because it is a property of
    # the CLI, and because it is the only failure mode in this script that ever erred towards
    # green: `900.0 >= "abc"` is false under awk's string comparison, so the slowest imaginable
    # suite passed. The fixture is 900 s so the case cannot succeed by being fast.
    for spec in "just-under.txt|yes||4.999 s passes under the default budget" \
                "just-over.txt|no||5.000 s fails under the default budget — the default is NFR-0.1's 5" \
                "very-slow.txt|no|--max abc|a non-numeric budget is rejected, not string-compared into a PASS" \
                "very-slow.txt|no|--max 5|900 s fails against a real budget, so the case above is not vacuous"; do
        IFS='|' read -r fixture expect extra note <<<"$spec"
        n=$((n + 1))
        printf '%d/%d  %-14s %s\n' "$n" "$total" "$fixture" "$note"

        # THIS script, not the one at a fixed path in the repo. A probe works by running a
        # modified copy, and a copy that re-invokes the original tests the wrong file — it reports
        # a mutation as caught when what actually failed was `no such file`. That is not
        # hypothetical either; it is how this line was written the first time.
        # shellcheck disable=SC2086  # $extra is a deliberate word-split of an option pair
        if env -u SUITE_RUNTIME_MAX bash "${BASH_SOURCE[0]}" $extra \
                --from "$scratch/$fixture" >/dev/null 2>&1; then
            actual="pass"
        else
            actual="fail"
        fi

        if [[ ( "$expect" == "yes" && "$actual" == "pass" ) || ( "$expect" == "no" && "$actual" == "fail" ) ]]; then
            echo "      ok    gate ${actual}ed, as required"
        else
            echo "      FAIL  gate ${actual}ed; the default budget is not 5 seconds." >&2
            failures=$((failures + 1))
        fi
    done

    echo
    if (( failures > 0 )); then
        echo "$failures/$total checks failed — the runtime gate is not proven." >&2
        exit 1
    fi
    echo "runtime gate verified: $total cases, 10 of them negative."
    exit 0
fi

# The gate proper.
if [[ -n "$FROM" ]]; then
    [[ -f "$FROM" ]] || { echo "check-suite-runtime.sh: no such file '$FROM'" >&2; exit 66; }
    check_output "$FROM" "$MAX"
    exit $?
fi

source "$REPO_ROOT/scripts/swift-strict-flags.sh"

captured="$(mktemp)"
trap 'rm -f "$captured"' EXIT

# Merged, per the header. Exit status is checked before the output is parsed, so a build failure
# and a slow suite stay distinguishable — the same reason the Linux job splits build from test.
if ! swift test --package-path "$PACKAGE" "${SWIFT_STRICT_FLAGS[@]}" >"$captured" 2>&1; then
    echo "FAIL  \`swift test\` exited non-zero; there is no duration to gate on." >&2
    echo >&2
    tail -30 "$captured" >&2
    exit 1
fi

check_output "$captured" "$MAX"
