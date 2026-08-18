#!/usr/bin/env bash
#
# Doc-comment to code ratio for the local Swift packages (G-6.3).
#
# Counts `///` lines against code lines across every package's Sources tree and fails when the
# aggregate ratio exceeds the maximum. Keeps the doc-comment trim from growing back.
#
# Two globs, one per level: the feature modules (TR-1.3) sit at Packages/Features/<Name>/, a level
# deeper than every other package, so `Packages/*/Sources` alone would leave the whole of Phase 1's
# feature code outside the gate.
#
#   scripts/check-doc-ratio.sh                    # the gate: aggregate max 1.5
#   scripts/check-doc-ratio.sh --max 1.2          # tighter, for a local experiment
#   scripts/check-doc-ratio.sh --per-file         # report every file, still gate on the aggregate
#
# The gate is deliberately an **aggregate** figure and deliberately not per-file. A per-file rule
# measures how declarative a file is rather than how wordy it is: an enum whose body is eight
# `case` lines cannot document what its cases mean inside a 1:1 budget, while a file with real
# function bodies passes without trying. Capping the total is what actually holds the line on
# argument-in-a-doc-comment, which is what the writing standard is about.
#
# What counts:
#   doc     a line whose first non-space characters are `///`
#   code    any other non-blank line outside a comment
#   ignored blank lines, `//` line comments, and everything inside `/* ... */`
#
# Requires python3 (present on macOS with the Xcode command line tools). Runs in the lint job.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MAX="${DOC_RATIO_MAX:-1.5}"
PER_FILE=0

usage() {
    # The header block above, minus the shebang, up to the first blank/non-comment line.
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --max)      MAX="$2"; shift 2 ;;
        --per-file) PER_FILE=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        *) echo "check-doc-ratio.sh: unknown argument '$1'" >&2; exit 64 ;;
    esac
done

cd "$REPO_ROOT"

MAX="$MAX" PER_FILE="$PER_FILE" python3 - <<'PY'
import os
import pathlib
import sys

maximum = float(os.environ["MAX"])
per_file = os.environ["PER_FILE"] == "1"


def count(path):
    """Doc and code line counts for one Swift file."""
    doc = code = 0
    in_block = False
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if in_block:
            if "*/" in stripped:
                in_block = False
            continue
        if stripped.startswith("/*"):
            if "*/" not in stripped:
                in_block = True
            continue
        if not stripped:
            continue
        if stripped.startswith("///"):
            doc += 1
        elif stripped.startswith("//"):
            continue
        else:
            code += 1
    return doc, code


root = pathlib.Path(".")
files = sorted(
    set(root.glob("Packages/*/Sources/**/*.swift")) | set(root.glob("Packages/*/*/Sources/**/*.swift"))
)
if not files:
    print("check-doc-ratio.sh: no sources found under Packages/**/Sources", file=sys.stderr)
    sys.exit(1)

total_doc = total_code = 0
rows = []
for path in files:
    doc, code = count(path)
    total_doc += doc
    total_code += code
    rows.append((path, doc, code))

if per_file:
    for path, doc, code in sorted(rows, key=lambda r: -(r[1] / r[2] if r[2] else 0)):
        ratio = f"{doc / code:.2f}" if code else "-"
        print(f"  {ratio:>6}  {doc:>5} doc  {code:>5} code   {path}")
    print()

ratio = total_doc / total_code if total_code else 0.0
verdict = "PASS" if ratio <= maximum else "FAIL"
print(
    f"Packages/**/Sources  doc={total_doc}  code={total_code}  "
    f"ratio={ratio:.2f}  (max {maximum:.2f})  {verdict}"
)

if verdict == "FAIL":
    excess = total_doc - int(maximum * total_code)
    print(
        f"\nDoc comments outweigh code by more than {maximum:.2f}:1 — about {excess} doc lines over.\n"
        "A doc comment states the decision, never the deliberation. Cut how a decision was\n"
        "reached, measured evidence (move it beside the assertion that pins it), restatements of\n"
        "module-wide rules, and task or gap IDs. See the writing standard in CLAUDE.md.\n"
        "Run with --per-file to see the worst offenders.",
        file=sys.stderr,
    )
    sys.exit(1)
PY
