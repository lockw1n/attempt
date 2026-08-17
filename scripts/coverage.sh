#!/usr/bin/env bash
#
# G-6.1: PowerliftingCore maintains >= 90% line coverage. No exceptions.
#
#   scripts/coverage.sh                                  # the gate: run the suite, measure, compare
#   scripts/coverage.sh --threshold 50                   # looser, for a local experiment
#   scripts/coverage.sh --package-path Packages/Persistence --package Persistence
#   scripts/coverage.sh --from FILE                      # gate a recorded llvm-cov export
#   scripts/coverage.sh --self-test                      # prove the gate fires, in both directions
#
# Runs the package's tests with coverage collection, then reports line coverage for its
# *production* sources only. Exits non-zero when the figure is below the threshold.
#
# THE COMPARISON IS NOT STRICT, AND THAT IS A REAL DIFFERENCE FROM ITS SIBLING GATE. G-6.1 says
# ">= 90%", so a reading of exactly 90.00 PASSES. check-suite-runtime.sh reads NFR-0.1's "under 5
# seconds" and rejects exactly the budget. The two gates look like copies of each other and differ
# on this one point; both boundaries are pinned by --self-test so neither can drift into the other.
#
# WHY 90 AND NOT SOMETHING NEAR THE CURRENT READING. PowerliftingCore has sat at 100% since T-0.10,
# so the gate has never fired and cannot fire today. That is an argument for a fixture, never for a
# tighter number: 90 is what G-6.1 says and no other figure has a requirement behind it. The remedy
# for "nobody has watched it fail" is --self-test, which watches it fail fifteen ways on every push.
#
# WHY THE Sources/ FILTER MATTERS. `swift test --show-codecov-path` yields an llvm-cov export whose
# `totals` covers every file in the test binary — including the test target's own sources and the
# runner Swift Testing generates under .build/**.derived/. Measured that way, PowerliftingCore
# reported 85% line coverage on the day it contained no executable code at all. G-6.1 is a claim
# about the domain layer, so only files under <package>/Sources/ are counted. Never gate on `totals`.
#
# WHAT COUNTS AS A FAILURE, AND WHY THEY ARE TOLD APART. Five outcomes call for five different
# fixes, so each has its own exit status and its own message. A gate that reports the wrong reason
# is worse than one that stays green, because it sends the fix to the wrong place.
#
#    0   at or above the threshold
#    1   below the threshold — a real coverage regression
#   64   usage: an unknown argument, a flag missing its value, or a threshold that is not a number
#        in 0...100
#   65   the report exists but could not be read — malformed JSON, bytes that are not UTF-8, a
#        shape llvm-cov no longer emits, or an I/O error opening it. Fails closed on purpose: a
#        parser that has silently stopped matching looks exactly like a module with nothing to
#        measure, and a truncated report must never be reported as a coverage regression
#   66   --from names no file, or --package-path names no directory
#   69   the report is well-formed and measures nothing. Two distinct causes, distinguished in the
#        message: NO file under Sources/ appears in the report at all (the filter matched nothing —
#        a wrong --package-path, or Sources/ moved), or files matched but carry zero executable
#        lines (a comments-only module). Both were a PASS before T-0.61 and both are bugs
#   70   the suite ran but produced no coverage report
#
# Requires: a Swift 6.2+ toolchain and python3 (present on macOS with the Xcode command line
# tools). The Linux job (T-0.08) builds and tests but does not call this script.

set -euo pipefail

# The gate turns on a decimal comparison and prints decimal figures. Same hardening as
# check-suite-runtime.sh, and recorded the same way: no case was found where it changes an outcome.
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PACKAGE_PATH="Packages/PowerliftingCore"
PACKAGE_NAME=""
THRESHOLD="${COVERAGE_THRESHOLD:-90}"
FROM=""
SELF_TEST=0

usage() {
    # The header block above, minus the shebang, up to the first blank/non-comment line.
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

need_value() {
    [[ $# -ge 2 ]] || { echo "coverage.sh: $1 needs a value" >&2; exit 64; }
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --package-path) need_value "$@"; PACKAGE_PATH="$2"; shift 2 ;;
        --package)      need_value "$@"; PACKAGE_NAME="$2"; shift 2 ;;
        --threshold)    need_value "$@"; THRESHOLD="$2"; shift 2 ;;
        --from)         need_value "$@"; FROM="$2"; shift 2 ;;
        --self-test)    SELF_TEST=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        *) echo "coverage.sh: unknown argument '$1'" >&2; exit 64 ;;
    esac
done

# --self-test: canned runs through the real CLI, most of which must fail; the script prints both
# counts rather than this comment naming them, so they cannot drift. The positive cases are not
# padding — a script that rejected everything would satisfy "has been seen to fire" while gating
# nothing, which is the failure mode verify-lint-rules.sh exists to catch.
#
# Every case goes through `bash "${BASH_SOURCE[0]}"` rather than a sourced function, because the
# parser lives in an embedded python program and there is no smaller unit to call. THIS script, not
# the one at a fixed repo path: a mutation probe works by running a modified *copy*, and a copy that
# re-invokes the original reports a mutation as caught when what actually failed was `no such file`.
#
# Each negative case asserts WHICH failure fired — the exit status AND the message — not merely
# that one did. Asserting the status alone lets any check stand in for any other; T-0.24 shipped
# that bug and a probe found it reporting "the suite did not pass" about a suite that had passed
# twice. Here the exposure is identical: "below threshold", "nothing under Sources/", "zero
# executable lines" and "unreadable report" are four different fixes.
#
# Most cases pass NO threshold, with $COVERAGE_THRESHOLD unset, so they see the DEFAULT — the one
# number G-6.1 actually specifies, and the number a probe cannot otherwise reach. They bracket 90
# rather than sitting under it. The flag and the environment variable get their own cases, so that
# bracketing cannot be satisfied by a hardcoded figure downstream of them. --package is defaulted
# the same way and for the same reason: only one case passes it.
#
# $GITHUB_STEP_SUMMARY is unset for the same reason it is unset in reverse — under Actions this
# step would otherwise append twenty fixture reports, most of them failures, to the run page
# directly beneath the real one. The `publishes` field turns it back on for the cases that assert
# what gets published; those are the only probes the run-summary path has.
#
# The two `-u`s are themselves unprobeable from inside a clean environment, which is the one known
# hole in this suite: a mutation deleting either survives, because there is nothing to leak in.
if (( SELF_TEST )); then
    scratch="$(mktemp -d)"
    trap 'rm -rf "$scratch"' EXIT

    pkg="$scratch/FakePackage"
    mkdir -p "$pkg/Sources" "$pkg/Tests"

    # make_report OUT ENTRY...  where ENTRY is  relative/path.swift:lineCount:linesCovered
    # Emits the subset of llvm-cov's export schema this script actually reads.
    make_report() {
        local out="$1"; shift
        python3 - "$out" "$pkg" "$@" <<'PYTHON'
import json
import sys

out, package = sys.argv[1:3]
files = []
for spec in sys.argv[3:]:
    relative, count, covered = spec.rsplit(":", 2)
    count, covered = int(count), int(covered)
    files.append({
        "filename": f"{package}/{relative}",
        "summary": {
            "lines": {
                "count": count,
                "covered": covered,
                "percent": (100.0 * covered / count) if count else 0.0,
            }
        },
    })
with open(out, "w") as handle:
    json.dump({"data": [{"files": files}]}, handle)
PYTHON
    }

    make_report "$scratch/healthy.json"    "Sources/Weight.swift:100:100"
    make_report "$scratch/just-under.json" "Sources/Weight.swift:1000:899"
    make_report "$scratch/boundary.json"   "Sources/Weight.swift:10:9"
    # 89.9999%, which "%.2f" renders as "90.00" — next to a FAIL against a threshold of 90 that
    # reads as a bug in the gate rather than in the coverage. floor2 is what stops it.
    make_report "$scratch/flatters.json"   "Sources/Weight.swift:1000000:899999"
    # Sources/ at 50%, drowned by a well-covered test target and Swift Testing's generated runner.
    # Unfiltered this is 1450/1500 = 96.66% and PASSES, so removing the filter flips the verdict as
    # well as the number — the single property T-0.04 built this script for.
    make_report "$scratch/inflated.json" \
        "Sources/Weight.swift:100:50" \
        "Tests/PowerliftingCoreTests/WeightTests.swift:900:900" \
        ".build/PowerliftingCorePackageTests.derived/runner.swift:500:500"
    # Nothing under Sources/ at all: the filter matched no files. Before T-0.61 this scored a PASS,
    # which is the same hole check-harness-excluded.sh was fixed for — a search over a path that no
    # longer exists reports success, and that is indistinguishable from a real pass.
    make_report "$scratch/no-sources.json" \
        "Tests/PowerliftingCoreTests/WeightTests.swift:900:900"
    # The degenerate population size, separately from the case above: zero files, not merely zero
    # matching files. A filter written to skip the wrong entries behaves differently on an empty list.
    make_report "$scratch/empty.json"
    # Files matched, but llvm-cov recorded no line records for them — a comments-only module. A
    # different fix from no-sources.json, so it must produce a different message.
    make_report "$scratch/zero-lines.json"  "Sources/Weight.swift:0:0"

    printf 'not json at all\n' >"$scratch/not-json.txt"
    # Bytes that are not UTF-8 — a truncated or half-written export. Written through python3 rather
    # than printf '\xff', whose escape handling is not the same in bash 3.2 as in bash 5.
    python3 -c 'import sys; open(sys.argv[1], "wb").write(bytes([0xff, 0xfe, 0x00, 0x01]))' \
        "$scratch/not-utf8.json"
    printf '{"data": []}\n'    >"$scratch/wrong-shape.json"
    printf '{"data": [{"files": [{"filename": "%s/Sources/Weight.swift"}]}]}\n' "$pkg" \
        >"$scratch/missing-summary.json"

    # The last three lines that carry information, for the diagnostic when a case fails. Blank
    # lines and the table's rules are dropped: a run that ends in two rows of dashes tells the
    # reader nothing about why it ended, and that is what `tail -3` alone produced here.
    said() {
        grep -vE '^[[:space:]]*$|^-+$' <<<"$1" | tail -3 | tr '\n' ' '
    }

    # fixture | extra args | expected exit | expected output | what it pins | env | published
    #
    # An EMPTY fixture passes no --from at all, and is only for cases that fail while parsing
    # arguments — anything reaching the body would try to `swift test` this fake package.
    # A non-empty `published` runs the case with $GITHUB_STEP_SUMMARY set and asserts that text
    # reaches the file.
    cases=(
        "healthy.json||0|TOTAL: 100.00% (threshold 90%) — PASS|a fully covered module is accepted||✅ **PASS** — 100.00% against a 90% threshold."
        "healthy.json||0|100/100    Sources/Weight.swift|the per-file breakdown names files relative to the package"
        "just-under.json||1|TOTAL: 89.90% (threshold 90%) — FAIL|below the default threshold fails"
        "boundary.json||0|TOTAL: 90.00% (threshold 90%) — PASS|exactly 90.00 passes — G-6.1 says *at least*"
        "flatters.json||1|TOTAL: 89.99% (threshold 90%) — FAIL|the printed figure never flatters the verdict"
        "inflated.json||1|TOTAL: 50.00% (threshold 90%) — FAIL|Sources/ only — the test target cannot lift the figure"
        "no-sources.json||69|no files under Sources/|a filter matching nothing fails *as such*, not as a pass||❌ **No files under \`Sources/\`**"
        "empty.json||69|no files under Sources/|a report with zero files is the same failure"
        "zero-lines.json||69|FakePackage's Sources/ has no executable lines|zero executable lines fails, with its own message — under the name --package defaults to"
        "zero-lines.json|--package Renamed|69|Renamed's Sources/ has no executable lines|--package overrides that default, so the case above is not vacuous"
        "not-json.txt||65|the coverage report could not be read|malformed JSON fails closed"
        "not-utf8.json||65|the coverage report could not be read|a non-UTF-8 report fails closed, rather than as a coverage regression"
        "wrong-shape.json||65|the coverage report could not be read|a shape llvm-cov no longer emits fails closed"
        "missing-summary.json||65|the coverage report could not be read|a file entry with no summary fails closed"
        "just-under.json|--threshold 50|0|(threshold 50%) — PASS|--threshold is honoured downwards"
        "boundary.json|--threshold 100|1|(threshold 100%) — FAIL|--threshold is honoured upwards, so the 90.00 case is not vacuous"
        "just-under.json||0|(threshold 50%) — PASS|\$COVERAGE_THRESHOLD is honoured|COVERAGE_THRESHOLD=50"
        "healthy.json|--threshold abc|64|--threshold must be a number|a non-numeric threshold is rejected, not string-compared into a PASS"
        "healthy.json|--threshold 101|64|--threshold must be a number|a threshold above 100 is rejected"
        "healthy.json|--flibble|64|unknown argument|an unknown argument is rejected"
        "|--threshold|64|--threshold needs a value|a flag with no value is rejected, not silently given the next one"
        "absent.json||66|no such file|--from naming no file fails, rather than measuring nothing"
        "healthy.json|--package-path SCRATCH/nope|66|no package at|--package-path naming no directory fails"
    )

    failures=0
    negatives=0
    n=0
    total=${#cases[@]}

    for spec in "${cases[@]}"; do
        IFS='|' read -r fixture extra expected_exit expected_output note envspec published <<<"$spec"
        n=$((n + 1))
        printf '%d/%d  %-20s %s\n' "$n" "$total" "${fixture:-—}" "$note"
        [[ "$expected_exit" == 0 ]] || negatives=$((negatives + 1))

        extra="${extra//SCRATCH/$scratch}"

        # $COVERAGE_THRESHOLD is unset for every case, then set again only where the case says so.
        # Without the unset, an exported value in the calling shell would silently replace the
        # default in the cases that pass no --threshold — and the default is the only number G-6.1
        # actually specifies. $GITHUB_STEP_SUMMARY is unset so that running this under Actions does
        # not publish the fixtures; the assignment below re-adds it for the cases that assert one.
        # Options before operands: env rejects a `-u` that follows a NAME=VALUE.
        env_prefix=(env -u COVERAGE_THRESHOLD -u GITHUB_STEP_SUMMARY)
        [[ -z "$envspec" ]] || env_prefix+=("$envspec")

        published_file="$scratch/published-$n.md"
        [[ -z "$published" ]] || env_prefix+=("GITHUB_STEP_SUMMARY=$published_file")

        # An empty fixture means no --from, for the cases that fail during argument parsing.
        # bash 3.2 has no empty-array expansion under `set -u`, hence the guard.
        from_args=()
        [[ -z "$fixture" ]] || from_args=(--from "$scratch/$fixture")

        set +e
        # shellcheck disable=SC2086  # $extra is a deliberate word-split of option pairs
        output="$("${env_prefix[@]}" bash "${BASH_SOURCE[0]}" \
            --package-path "$pkg" $extra \
            ${from_args[@]+"${from_args[@]}"} 2>&1)"
        actual_exit=$?
        set -e

        if [[ "$actual_exit" -ne "$expected_exit" ]]; then
            echo "      FAIL  exited $actual_exit, expected $expected_exit." >&2
            echo "            said: $(said "$output")" >&2
            failures=$((failures + 1))
        # `-e` is load-bearing, not decoration: three of the expected messages begin with `--`,
        # which grep reads as an option and rejects. Without it those cases printed a usage error
        # and were scored as "right status, wrong reason" — a false red, but the mirror-image bug
        # (an assertion that silently matches nothing) is the one that would have gone unnoticed.
        elif ! grep -qF -e "$expected_output" <<<"$output"; then
            echo "      FAIL  exited $actual_exit as required, but for the wrong reason." >&2
            echo "            expected to say: $expected_output" >&2
            echo "            actually said:   $(said "$output")" >&2
            failures=$((failures + 1))
        # The run summary is a separate stream from the console, so a case asserting one has to
        # read the file. Without this the whole publishing path is unprobed — replacing the body of
        # publish() with a no-op passed every console assertion.
        elif [[ -n "$published" ]] && ! grep -qF -e "$published" "$published_file" 2>/dev/null; then
            echo "      FAIL  exited $actual_exit as required, but published the wrong summary." >&2
            echo "            expected to publish: $published" >&2
            echo "            actually published:  $(said "$(cat "$published_file" 2>/dev/null)")" >&2
            failures=$((failures + 1))
        else
            echo "      ok    exited $actual_exit, saying \"$expected_output\""
        fi
    done

    echo
    if (( failures > 0 )); then
        echo "$failures/$total checks failed — the coverage gate is not proven." >&2
        exit 1
    fi
    echo "coverage gate verified: $total cases, $negatives of them negative."
    exit 0
fi

if [[ "$PACKAGE_PATH" = /* ]]; then
    ABS_PACKAGE_PATH="$PACKAGE_PATH"
else
    ABS_PACKAGE_PATH="$REPO_ROOT/$PACKAGE_PATH"
fi

# Validated before the suite runs, not in the Python below, which only starts after the whole
# suite — a typo'd threshold should cost a second, not a build, and should read as a message and
# not a stack trace. Erring green is the failure mode that goes unnoticed: an unvalidated
# non-numeric threshold is exactly how check-suite-runtime.sh once reported PASS on a 900-second
# suite, because awk string-compares unless both operands look numeric.
if ! [[ "$THRESHOLD" =~ ^([0-9]+|[0-9]*\.[0-9]+)$ ]] || ! awk -v t="$THRESHOLD" 'BEGIN { exit !(t <= 100) }'; then
    echo "coverage.sh: --threshold must be a number between 0 and 100, got '$THRESHOLD'" >&2
    echo "      Set it with --threshold or \$COVERAGE_THRESHOLD. G-6.1's figure is 90." >&2
    exit 64
fi

[[ -d "$ABS_PACKAGE_PATH" ]] || { echo "coverage.sh: no package at $ABS_PACKAGE_PATH" >&2; exit 66; }
[[ -n "$PACKAGE_NAME" ]] || PACKAGE_NAME="$(basename "$PACKAGE_PATH")"

if [[ -n "$FROM" ]]; then
    # Gate a recorded export instead of producing one. This is what makes --self-test possible:
    # the alternative done-when — break a file, watch CI redden, revert — proves the gate fired on
    # the afternoon someone tried it and nothing about its state today.
    [[ -f "$FROM" ]] || { echo "coverage.sh: no such file '$FROM'" >&2; exit 66; }
    CODECOV_JSON="$FROM"
else
    # G-6.4: the strict flags travel with every build path, this one included. Without them this
    # script would compile the suite with warnings merely warned about, quietly creating a hole in
    # the gate for exactly the code the coverage number is about. See scripts/swift-strict-flags.sh.
    source "$REPO_ROOT/scripts/swift-strict-flags.sh"

    echo "==> Testing $PACKAGE_NAME with coverage"
    swift test --package-path "$ABS_PACKAGE_PATH" --enable-code-coverage "${SWIFT_STRICT_FLAGS[@]}"

    CODECOV_JSON="$(swift test --package-path "$ABS_PACKAGE_PATH" --enable-code-coverage "${SWIFT_STRICT_FLAGS[@]}" --show-codecov-path | tail -1)"
    [[ -f "$CODECOV_JSON" ]] || { echo "coverage.sh: no coverage report at $CODECOV_JSON" >&2; exit 70; }
fi

# `-u` is not a preference. Python block-buffers stdout when it is a pipe and never buffers stderr,
# so under a merged capture — `2>&1`, which is how CI logs and --self-test both read this — the
# error message arrives BEFORE the table it is about. The failure then looks like it happened to a
# different run. Unbuffered, the two streams interleave in the order they were written.
python3 -u - "$CODECOV_JSON" "$ABS_PACKAGE_PATH" "$PACKAGE_NAME" "$THRESHOLD" <<'PYTHON'
import json
import math
import os
import sys

report_path, package_path, package_name, threshold = sys.argv[1:5]
threshold = float(threshold)

EX_DATAERR = 65      # the report exists but cannot be read
EX_UNAVAILABLE = 69  # the report is well-formed and measures nothing


def floor2(value):
    """Round *down* to 2dp, so the printed figure never flatters the verdict.

    Printing `%.2f` of 89.999 gives "90.00%" next to a FAIL against a threshold of 90, which
    reads as a bug in the gate rather than in the coverage.
    """
    return math.floor(value * 100) / 100


# TR-0.6.1 (T-0.07): the same numbers also go to the GitHub run summary when running in Actions,
# so a reviewer sees coverage on the run page instead of unfolding a log. Appended, never
# truncated — other steps may write here too. Outside Actions the variable is unset and this is a
# no-op, which keeps local output identical to CI's.
summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
summary = []


def publish(*lines):
    if not summary_path:
        return
    summary.extend(lines)
    with open(summary_path, "a") as handle:
        handle.write("\n".join(summary) + "\n")


def unreadable(detail):
    """Exit 65. A report that cannot be parsed must never resemble one with nothing to measure."""
    print(f"\ncoverage.sh: the coverage report could not be read — {detail}", file=sys.stderr)
    print(f"      {report_path}", file=sys.stderr)
    print("      This is a failure and not a pass on purpose: a parser that has silently", file=sys.stderr)
    print("      stopped matching looks exactly like a module with no code in it. If", file=sys.stderr)
    print("      llvm-cov's export schema changed, fix the reader, then re-run --self-test.", file=sys.stderr)
    publish("", f"❌ **Unreadable coverage report** — {detail}.")
    sys.exit(EX_DATAERR)


try:
    with open(report_path) as handle:
        export = json.load(handle)
# Not JSONDecodeError alone. A truncated or non-UTF-8 export raises UnicodeDecodeError and an
# unreadable-but-present one raises OSError; either escaping as a traceback would exit 1, which is
# this script's code for a real coverage regression — the single worst place to send the fix.
# JSONDecodeError is a ValueError, so the malformed-JSON case is still caught here.
except (OSError, UnicodeDecodeError, ValueError) as error:
    unreadable(f"not readable as JSON ({type(error).__name__}: {error})")

# Production sources only: <package>/Sources/**, never Tests/ and never the generated runner.
sources_root = os.path.join(os.path.realpath(package_path), "Sources") + os.sep

counted, total, covered = [], 0, 0
try:
    for entry in export["data"][0]["files"]:
        # Resolved once and kept. Filtering on the resolved path and then displaying the raw one
        # makes the relative name below meaningless the moment any component is a symlink — on
        # macOS /var is one, so a report under a temporary directory printed `../../../..` all the
        # way to the root. Never visible for Packages/PowerliftingCore, which is why it has to be
        # pinned rather than eyeballed.
        resolved = os.path.realpath(entry["filename"])
        if not resolved.startswith(sources_root):
            continue
        lines = entry["summary"]["lines"]
        counted.append((resolved, int(lines["count"]), int(lines["covered"])))
        total += int(lines["count"])
        covered += int(lines["covered"])
except (AttributeError, IndexError, KeyError, TypeError, ValueError) as error:
    unreadable(f"unexpected shape ({type(error).__name__}: {error})")

print()
print(f"{package_name} line coverage (Sources/ only)")
print("-" * 60)
summary.append(f"### {package_name} line coverage")
summary.append("")
summary.append("Production sources only — `Sources/**`, excluding the test target and Swift")
summary.append("Testing's generated runner.")
summary.append("")
summary.append("| File | Lines | Covered |")
summary.append("|---|---:|---:|")
for filename, count, hit in sorted(counted, key=lambda item: item[0]):
    name = os.path.relpath(filename, os.path.realpath(package_path))
    percent = floor2(100.0 * hit / count) if count else 0.0
    print(f"  {percent:6.2f}%  {hit:5d}/{count:<5d}  {name}")
    summary.append(f"| `{name}` | {count} | {percent:.2f}% ({hit}) |")

if not counted:
    # The filter matched nothing. Until T-0.61 this scored a PASS, and it is the worst kind: a
    # renamed package, a moved Sources/ or a wrong --package-path all land here, and a gate that
    # searches nothing and reports success cannot be told apart from a gate that passed.
    print("-" * 60)
    print("\ncoverage.sh: no files under Sources/ appear in the coverage report.", file=sys.stderr)
    print(f"      Looked under: {sources_root}", file=sys.stderr)
    print("      Either --package-path names the wrong package, or the report belongs to a", file=sys.stderr)
    print("      different one. G-6.1 cannot be evidenced by a filter that matched no files,", file=sys.stderr)
    print("      so this is a hard failure rather than a vacuous 100%.", file=sys.stderr)
    publish("", "❌ **No files under `Sources/`** — the coverage filter matched nothing.")
    sys.exit(EX_UNAVAILABLE)

if total == 0:
    # Files matched, but llvm-cov emitted no line records for any of them — every source file is
    # comments-only. Correct as a PASS in T-0.04, when there was no code; a bug by exit review,
    # when a PowerliftingCore with zero executable lines is a deleted module, not a 100% score.
    # Unreachable in normal operation since T-0.10, hence pinned by --self-test rather than assumed.
    print("-" * 60)
    print(f"\ncoverage.sh: {package_name}'s Sources/ has no executable lines.", file=sys.stderr)
    print(f"      {len(counted)} file(s) matched, and llvm-cov recorded no line records for any", file=sys.stderr)
    print("      of them. There is no percentage to compute, so there is nothing to gate on —", file=sys.stderr)
    print("      and a module with no executable code cannot evidence G-6.1.", file=sys.stderr)
    publish("", "❌ **No executable lines** — nothing to measure, which is not a pass.")
    sys.exit(EX_UNAVAILABLE)

percent = 100.0 * covered / total
print("-" * 60)
print(f"  {floor2(percent):6.2f}%  {covered:5d}/{total:<5d}  TOTAL")

# NOT strict: G-6.1 says ">= 90%", so exactly the threshold passes. Its sibling gate reads
# NFR-0.1's "under 5 seconds" and rejects exactly the budget. Both boundaries are in --self-test.
verdict = "PASS" if percent >= threshold else "FAIL"
print(f"\nTOTAL: {floor2(percent):.2f}% (threshold {threshold:g}%) — {verdict}")

icon = "✅" if verdict == "PASS" else "❌"
summary.append(f"| **TOTAL** | **{total}** | **{floor2(percent):.2f}% ({covered})** |")
summary.append("")
summary.append(f"{icon} **{verdict}** — {floor2(percent):.2f}% against a {threshold:g}% threshold.")
if threshold < 90:
    summary.append("")
    summary.append("> This run's threshold is below `G-6.1`'s 90%, so it is a readout and not the gate.")
publish()

if verdict == "FAIL":
    sys.exit(1)
PYTHON
