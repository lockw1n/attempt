#!/usr/bin/env bash
#
# Units and valid ranges on the dimensioned public API (NFR-0.3, T-0.23).
#
#   scripts/check-doc-units.sh              # the gate
#   scripts/check-doc-units.sh --list       # every symbol checked, passing or not
#
# `missing_docs` measures whether a doc comment EXISTS. NFR-0.3 asks what it SAYS — "units and
# valid ranges" — and no lint rule can read that. This is the guard for the second half.
#
# **It is a proxy and it says so.** What it catches is the realistic regression: someone adds a
# public `reps: Int` or `percentage: Double` and writes a doc comment that never says what the
# number is measured in or what values are legal. What it cannot catch is prose that names a unit
# for the wrong quantity. The evidence that the surface is correctly documented today is the
# symbol-by-symbol audit in T-0.23's task file; this script only stops that audit rotting.
#
# ## What it checks, and why the population is this narrow
#
# Only public declarations that bind a **bare scalar** — Int, Double, or a ClosedRange of one —
# under a **dimensioned name**. `Weight` is excluded on purpose and that is the central idea: a
# `Weight` is grams by type (G-1.1), so it documents its own unit and a rule demanding the word
# "grams" beside every one of them would be pure noise. It is `reps: Int`, `rpe: Double` and
# `percentage: Double` that carry a quantity the type system does not, and those are exactly where
# NFR-0.3 bites.
#
# Function parameters, stored properties, static constants and enum-case associated values all
# count. Each must carry at least one UNIT token and at least one RANGE token. Both lists are
# below and both are deliberately short: a longer list passes more prose and gates less.
#
# ## Three deliberate exemptions, each encoding a policy rather than dodging one
#
# **A declaration inherits its enclosing type's doc block.** `Weight.grams` does not restate "any
# Int, including negative" because the type says it two lines up, and `ResolutionStep`'s cases do
# not restate an invariant that is about the whole enum. That is the one-home rule in CLAUDE.md's
# writing standard, and a gate that punished it would push the module toward the restatement the
# standard forbids.
#
# **A memberwise-style initialiser is skipped when every dimensioned label it takes names a
# property of the enclosing type.** The property is the quantity's home and is checked there;
# making `init(weight:setOffset:)` repeat `setOffset`'s range would be a second copy to keep in
# sync. An initialiser taking a dimensioned label that is *not* a property of its own type is
# checked normally — that one is introducing a quantity rather than storing one. Membership is
# per type and not per file, which matters: PersonalRecord.swift declares three types.
#
# **A constant bound to a literal is exempt from the RANGE half only.** `defaultPercentage = 0.9`
# has no range; it has a value. It still has to say what the value means, so the UNIT half stands.
#
# ## Parsing
#
# Line-based, which is enough for this tree and is stated so nobody assumes otherwise. Braces are
# counted only after string literals and `//` comments are stripped, because an unbalanced brace
# in either would silently mis-attribute enclosing-type docs — a failure that reads as success.
# Multi-line string literals (`"""`) are NOT handled; the module has none, and one would need a
# real lexer here. `checked == 0` is treated as a failure for the same family of reasons.
#
# Requires python3, as scripts/check-doc-ratio.sh does. Runs in the lint job.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST=0

usage() {
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)    LIST=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "check-doc-units.sh: unknown argument '$1'" >&2; exit 64 ;;
    esac
done

cd "$REPO_ROOT"

LIST="$LIST" python3 - <<'PY'
import os
import pathlib
import re
import sys

show_all = os.environ["LIST"] == "1"

SOURCES = "Packages/PowerliftingCore/Sources/**/*.swift"

# A name that carries a quantity the type does not. Matched case-insensitively against the binding
# label, as a substring, so `repsToFailure` and `fractionOfMax` are both caught by their stems.
DIMENSIONED = (
    "rep", "rpe", "rir", "percent", "fraction", "ratio",
    "gram", "milliunit", "pair", "count", "offset",
)

# Bare scalars only. `Weight` is grams by type (G-1.1) and is deliberately not here.
SCALAR = re.compile(r"^(Int|Double|ClosedRange<Int>|ClosedRange<Double>)\??$")

# What the quantity is measured in.
UNITS = (
    "gram", "kilogram", "pound", "milli-unit", "milli-kilogram", "milli-pound", "thousandth",
    "rep", "rpe", "rir", "ratio", "fraction", "percent", "dimensionless",
    "pair", "plate", "index", "position",
)

# What values are legal. A range statement, in any of the spellings this module actually uses.
# "unguarded" and "legal" are range statements too — the first says every value is accepted, which
# is a domain and not an absence of one; the second is how this module spells "zero counts".
RANGES = (
    "range", "at least", "within", "must be", "must not", "no more than",
    "zero-based", "zero", "non-negative", "negative", "upwards", "or above", "or below",
    "finite", "outside", "through", "any `int`", "bounded", "strictly", "legal", "unguarded",
    "greater than", "less than", "uncapped", "0 <", ">=", "≤", "…", "...",
)

DECL = re.compile(r"\b(public\s+(static\s+)?(let|var|func|init|subscript)|case\s+[a-z])")
TYPE_DECL = re.compile(r"\b(public\s+)?(struct|enum|class|actor|protocol)\s+(\w+)")
EXTENSION = re.compile(r"^\s*(public\s+)?extension\s+(\w+)")
PROPERTY = re.compile(r"\bpublic\s+(?:static\s+)?(?:let|var)\s+([a-z]\w*)")

# `label: Type` in a signature, or `label = literal` for an inferred constant.
BINDING = re.compile(r"\b([a-z]\w*)\s*:\s*([A-Za-z_][\w<>]*\??)")
INFERRED = re.compile(r"\b(?:let|var)\s+([a-z]\w*)\s*(?::\s*[\w<>?]+\s*)?=\s*(-?\d+(?:\.\d+)?)\b")

STRING = re.compile(r'"(?:\\.|[^"\\])*"')


def code_only(line):
    """`line` with string literals and any trailing `//` comment removed.

    Brace counting runs on this rather than the raw line. The module documents its own wire
    formats — `{"grams": 102500}` appears in several doc comments — so counting raw braces would
    corrupt the enclosing-type stack the moment one of those spanned two lines unbalanced.
    """
    return STRING.sub('""', line).split("//", 1)[0]


def is_dimensioned(label):
    lowered = label.lower()
    return any(stem in lowered for stem in DIMENSIONED)


def type_docs(lines):
    """Doc block per type declared in this file, so an `extension` can inherit it.

    A pre-pass rather than part of the walk below, so an extension appearing *before* the type it
    extends still inherits. Same file only: a cross-file extension (RPETableStandard.swift extends
    RPETable) inherits nothing, which is the conservative direction — it means more is checked.
    """
    docs = {}
    doc = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("///"):
            doc.append(stripped[3:])
            continue
        # An attribute or a blank line between a comment and its type must not detach the two.
        if not stripped or stripped.startswith("@"):
            continue
        match = TYPE_DECL.search(code_only(line))
        if match and doc:
            docs[match.group(3)] = "\n".join(doc)
        doc = []
    return docs


def bindings(signature):
    """Dimensioned bare-scalar labels this declaration introduces, and whether it is a literal."""
    found = []
    literal_only = True
    for label, kind in BINDING.findall(signature):
        if is_dimensioned(label) and SCALAR.match(kind):
            found.append(label)
            literal_only = False
    for label, _ in INFERRED.findall(signature):
        if is_dimensioned(label) and label not in found:
            found.append(label)
    return found, literal_only and bool(found)


def scan(path):
    """(declaration records, public properties per type) for one file.

    A record is (line, own doc, enclosing type doc, enclosing type name, signature). Both are
    produced by one walk so the property map is keyed by the same scope tracking the docs use.
    """
    lines = path.read_text().splitlines()
    declared = type_docs(lines)
    records = []
    properties = {}
    stack = []  # (brace depth the scope opened at, type name, that type's doc)
    depth = 0
    doc = []
    doc_line = 0
    index = 0

    while index < len(lines):
        stripped = lines[index].strip()

        if stripped.startswith("///"):
            if not doc:
                doc_line = index + 1
            doc.append(stripped[3:])
            index += 1
            continue
        if not stripped:
            doc = []
            index += 1
            continue
        if stripped.startswith("@"):
            index += 1
            continue

        # A declaration may wrap; take lines until the parentheses balance.
        signature = [lines[index]]
        code = code_only(lines[index])
        parens = code.count("(") - code.count(")")
        while parens > 0 and index + 1 < len(lines):
            index += 1
            signature.append(lines[index])
            more = code_only(lines[index])
            parens += more.count("(") - more.count(")")
            code += "\n" + more
        index += 1

        opened_at = depth
        depth += code.count("{") - code.count("}")
        while stack and depth <= stack[-1][0]:
            stack.pop()

        joined = "\n".join(signature)
        enclosing_name = stack[-1][1] if stack else None
        enclosing_doc = stack[-1][2] if stack else ""
        own_doc = "\n".join(doc)

        if own_doc:
            records.append((doc_line, own_doc, enclosing_doc, enclosing_name, joined))

        for label in PROPERTY.findall(code):
            properties.setdefault(enclosing_name, set()).add(label)

        if depth > opened_at:
            extended = EXTENSION.match(code)
            declaration = TYPE_DECL.search(code)
            if extended:
                name = extended.group(2)
                stack.append((opened_at, name, declared.get(name, "")))
            elif declaration:
                name = declaration.group(3)
                stack.append((opened_at, name, declared.get(name, own_doc)))

        doc = []

    return records, properties


failures = []
checked = 0

for path in sorted(pathlib.Path(".").glob(SOURCES)):
    records, properties = scan(path)

    for line, doc, inherited, enclosing, signature in records:
        if not DECL.search(signature):
            continue
        labels, is_literal = bindings(signature)
        if not labels:
            continue
        # A memberwise-style initialiser stores quantities documented on its own type's properties.
        owned = properties.get(enclosing, set())
        if re.search(r"\bpublic\s+init\b", signature) and all(label in owned for label in labels):
            continue
        lowered = (doc + "\n" + inherited).lower()
        has_unit = any(token in lowered for token in UNITS)
        has_range = is_literal or any(token in lowered for token in RANGES)
        checked += 1
        names = ", ".join(labels)
        if has_unit and has_range:
            if show_all:
                print(f"  ok    {path}:{line}  {names}")
            continue
        missing = []
        if not has_unit:
            missing.append("unit")
        if not has_range:
            missing.append("range")
        failures.append(f"  FAIL  {path}:{line}  {names} — no {' and no '.join(missing)}")

for failure in failures:
    print(failure)

# Flush before writing the summary, or stderr overtakes stdout and the count is printed above the
# failures it counts — which is exactly how this script's first run read.
sys.stdout.flush()

if failures:
    print(
        f"\n{len(failures)} of {checked} dimensioned public declarations do not state a unit and a "
        "valid range (NFR-0.3).\nSee T-0.23 for the policy: a bare Int or Double under a "
        "dimensioned name has to say what it measures and which values are legal.",
        file=sys.stderr,
    )
    sys.exit(1)

if checked == 0:
    print(
        "check-doc-units.sh: matched no declarations at all — the parser or the vocabulary is "
        "broken, which is a failure and not a pass.",
        file=sys.stderr,
    )
    sys.exit(1)

print(f"{checked} dimensioned public declarations state a unit and a valid range.")
PY
