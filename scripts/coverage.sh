#!/usr/bin/env bash
#
# Line coverage for a local Swift package (G-6.1, G-6.3).
#
# Runs the package's tests with coverage collection, then reports line coverage for its
# *production* sources only. Exits non-zero when the figure is below the threshold.
#
#   scripts/coverage.sh                                  # PowerliftingCore, threshold 0
#   scripts/coverage.sh --threshold 90                   # the G-6.1 gate (wired up in T-0.61)
#   scripts/coverage.sh --package-path Packages/Persistence --package Persistence
#
# The threshold defaults to 0 on purpose: T-0.04 builds the measuring instrument, T-0.61 turns
# it into a gate once there is code to measure. Override with --threshold or $COVERAGE_THRESHOLD.
#
# Why the filtering matters. `swift test --show-codecov-path` yields an llvm-cov export whose
# `totals` covers every file in the test binary — including the test target's own sources and the
# runner Swift Testing generates under .build/**.derived/. Measured that way, PowerliftingCore
# reported 85% line coverage on the day it contained no executable code at all. G-6.1 is a claim
# about the domain layer, so only files under <package>/Sources/ are counted.
#
# Requires: a Swift 6.2+ toolchain and python3 (present on macOS with the Xcode command line
# tools). The Linux job (T-0.08) builds and tests but does not call this script.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PACKAGE_PATH="Packages/PowerliftingCore"
PACKAGE_NAME=""
THRESHOLD="${COVERAGE_THRESHOLD:-0}"

usage() {
    # The header block above, minus the shebang, up to the first blank/non-comment line.
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --package-path) PACKAGE_PATH="$2"; shift 2 ;;
        --package)      PACKAGE_NAME="$2"; shift 2 ;;
        --threshold)    THRESHOLD="$2"; shift 2 ;;
        -h|--help)      usage; exit 0 ;;
        *) echo "coverage.sh: unknown argument '$1'" >&2; exit 64 ;;
    esac
done

# Validated here rather than in the Python below, which only runs after the full test suite —
# a typo'd threshold should cost a second, not a build, and should read as a message not a
# stack trace.
if ! [[ "$THRESHOLD" =~ ^([0-9]+|[0-9]*\.[0-9]+)$ ]] || ! awk -v t="$THRESHOLD" 'BEGIN { exit !(t <= 100) }'; then
    echo "coverage.sh: --threshold must be a number between 0 and 100, got '$THRESHOLD'" >&2
    exit 64
fi

ABS_PACKAGE_PATH="$REPO_ROOT/$PACKAGE_PATH"
[[ -d "$ABS_PACKAGE_PATH" ]] || { echo "coverage.sh: no package at $ABS_PACKAGE_PATH" >&2; exit 66; }
[[ -n "$PACKAGE_NAME" ]] || PACKAGE_NAME="$(basename "$PACKAGE_PATH")"

echo "==> Testing $PACKAGE_NAME with coverage"
swift test --package-path "$ABS_PACKAGE_PATH" --enable-code-coverage

CODECOV_JSON="$(swift test --package-path "$ABS_PACKAGE_PATH" --enable-code-coverage --show-codecov-path | tail -1)"
[[ -f "$CODECOV_JSON" ]] || { echo "coverage.sh: no coverage report at $CODECOV_JSON" >&2; exit 70; }

python3 - "$CODECOV_JSON" "$ABS_PACKAGE_PATH" "$PACKAGE_NAME" "$THRESHOLD" <<'PYTHON'
import json
import math
import os
import sys

report_path, package_path, package_name, threshold = sys.argv[1:5]
threshold = float(threshold)


def floor2(value):
    """Round *down* to 2dp, so the printed figure never flatters the verdict.

    Printing `%.2f` of 89.999 gives "90.00%" next to a FAIL against a threshold of 90, which
    reads as a bug in the gate rather than in the coverage.
    """
    return math.floor(value * 100) / 100

with open(report_path) as handle:
    export = json.load(handle)

# Production sources only: <package>/Sources/**, never Tests/ and never the generated runner.
sources_root = os.path.join(os.path.realpath(package_path), "Sources") + os.sep

counted, total, covered = [], 0, 0
for entry in export["data"][0]["files"]:
    if not os.path.realpath(entry["filename"]).startswith(sources_root):
        continue
    lines = entry["summary"]["lines"]
    counted.append((entry["filename"], lines))
    total += lines["count"]
    covered += lines["covered"]

print()
print(f"{package_name} line coverage (Sources/ only)")
print("-" * 60)
for filename, lines in sorted(counted, key=lambda item: item[0]):
    name = os.path.relpath(filename, os.path.realpath(package_path))
    print(f"  {floor2(lines['percent']):6.2f}%  {lines['covered']:5d}/{lines['count']:<5d}  {name}")

if total == 0:
    # Every source file is comments-only, so llvm-cov emits no line records at all. There is no
    # percentage to compute and nothing to gate on. Reported as a pass with a warning until real
    # code lands — T-0.61 should make this state a hard failure, because a PowerliftingCore with
    # zero executable lines at exit review is a bug, not a 100% score.
    print("-" * 60)
    print("  no executable lines found — nothing to measure yet")
    print(f"\nTOTAL: n/a (threshold {threshold:g}%) — PASS (nothing to measure)")
    sys.exit(0)

percent = 100.0 * covered / total
print("-" * 60)
print(f"  {floor2(percent):6.2f}%  {covered:5d}/{total:<5d}  TOTAL")

verdict = "PASS" if percent >= threshold else "FAIL"
print(f"\nTOTAL: {floor2(percent):.2f}% (threshold {threshold:g}%) — {verdict}")

if verdict == "FAIL":
    sys.exit(1)
PYTHON
