#!/usr/bin/env bash
#
# G-6.4: no `@unchecked Sendable` without a written justification comment.
#
#   scripts/audit-unchecked-sendable.sh              # audit the default roots
#   scripts/audit-unchecked-sendable.sh Packages     # audit specific roots
#
# `@unchecked Sendable` is an assertion the compiler cannot check, so G-6.4 requires the author to
# write down why it is true. This makes that mechanical instead of a review habit: every
# occurrence must carry the marker
#
#     Sendable justification: <why this type is actually safe to share across isolation domains>
#
# either as a trailing comment on the same line, or anywhere in the contiguous comment block
# directly above the declaration. Exits 1 listing every unjustified occurrence.
#
# Only *code* is audited: prose about the annotation is not a use of it, so a doc comment reading
# "never reach for @unchecked Sendable" is ignored rather than flagged.
#
# Why a script and not a lint rule. SwiftLint's `custom_rules` can match the annotation but cannot
# see the lines above it, so it can only ban `@unchecked Sendable` outright or allow it silently —
# neither is what G-6.4 asks for. `.swiftlint.yml` also does not cover `Packages/` yet (T-0.05).
# If T-0.05 finds a linter that can express the lookback, this script should be retired into it.
#
# Requires: python3 (present on macOS with the Xcode command line tools; on the Linux CI image it
# comes from the container base — T-0.08).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Everything that holds first-party Swift: the three packages and the app target. `.build/` is
# excluded in the walk below — it holds compiled dependencies and generated test runners, whose
# annotations are not ours to justify.
ROOTS=("$@")
[[ ${#ROOTS[@]} -gt 0 ]] || ROOTS=("Packages" "Attempt")

python3 - "$REPO_ROOT" "${ROOTS[@]}" <<'PYTHON'
import os
import re
import sys

repo_root, roots = sys.argv[1], sys.argv[2:]

ANNOTATION = re.compile(r"@unchecked\s+Sendable")
MARKER = "Sendable justification:"
SKIPPED_DIRS = {".build", ".git", "DerivedData", ".swiftpm"}


def code_part(line):
    """The line with any `//` comment removed, or "" if the whole line is comment.

    Without this, prose *about* the annotation is flagged as a use of it — and the constraints
    block at the top of PowerliftingCore.swift is exactly where someone writes "never reach for
    @unchecked Sendable". A false positive there is worse than a miss: the quickest way to silence
    it is to paste a justification marker onto a line that justifies nothing, which turns the
    audit's own signal into noise.

    Naive on purpose. It does not track string literals or nested block comments, because a
    `@unchecked Sendable` inside a string is not a thing anyone writes, and being wrong about it
    costs one comment. Being wrong about doc comments would cost the audit its credibility.
    """
    stripped = line.lstrip()
    if stripped.startswith(("//", "*", "/*")):
        return ""
    return line.split("//", 1)[0]

violations = []
checked_files = 0
justified = 0

for root in roots:
    for dirpath, dirnames, filenames in os.walk(os.path.join(repo_root, root)):
        dirnames[:] = [d for d in dirnames if d not in SKIPPED_DIRS]
        for filename in sorted(filenames):
            if not filename.endswith(".swift"):
                continue
            path = os.path.join(dirpath, filename)
            checked_files += 1
            with open(path, encoding="utf-8") as handle:
                lines = handle.read().splitlines()

            for index, line in enumerate(lines):
                if not ANNOTATION.search(code_part(line)):
                    continue

                # Same-line trailing comment, or the contiguous comment block directly above.
                # Blank lines end the block: a justification separated from its declaration is
                # not attached to it, and will drift away from it on the next edit.
                context = [line]
                cursor = index - 1
                while cursor >= 0 and lines[cursor].lstrip().startswith(("//", "///", "*", "/*")):
                    context.append(lines[cursor])
                    cursor -= 1

                if any(MARKER in candidate for candidate in context):
                    justified += 1
                else:
                    violations.append((os.path.relpath(path, repo_root), index + 1, line.strip()))

print(f"==> @unchecked Sendable audit (G-6.4): {checked_files} Swift file(s) in {', '.join(roots)}")

if violations:
    print(f"\n{len(violations)} unjustified occurrence(s):\n")
    for path, line_number, text in violations:
        print(f"  {path}:{line_number}")
        print(f"      {text}")
    print(
        f"\nEach needs a comment containing '{MARKER}' on the same line or immediately above it.\n"
        "If the type can be made safely Sendable instead, do that — G-6.4 permits the escape "
        "hatch, it does not encourage it."
    )
    sys.exit(1)

if justified:
    print(f"    {justified} occurrence(s), all justified — PASS")
else:
    print("    no occurrences — PASS")
PYTHON
