#!/usr/bin/env bash
#
# T-0.05: prove the configured SwiftLint rules actually fire.
#
#   scripts/verify-lint-rules.sh
#
# Mostly the custom rules, but not only them: `missing_docs` (T-0.23) is a built-in whose default
# configuration gates nothing on this repo, so it needs the same proof a custom rule does. What is
# checked here is "a rule we rely on, whose enforcement is invisible when it silently stops working".
#
# `swiftlint lint --strict` passing tells you the tree is clean. It does not tell you the rules
# work — a typo in a `regex:`, a path filter that matches nothing, or a rule silently dropped by a
# SwiftLint upgrade all leave you with a green run and no enforcement. That failure mode is
# invisible precisely because it looks like success, which is why T-0.05's "done when" asks for a
# fixture per rule: an unfireable rule is worse than no rule, because it reads as coverage.
#
# Two directions are checked:
#
#   POSITIVE  each fixture under scripts/lint-fixtures/ must trigger its rule.
#   NEGATIVE  files that merely *mention* a banned import in prose must NOT trigger it.
#             PowerliftingCore.swift and Persistence.swift both document the rules they are
#             subject to, so the import bans rely on `match_kinds` to skip `comment` syntax.
#             Without that they would fire on the very files explaining them.
#             `no_imports_in_core` (T-0.14) is anchored to the start of a line, so a `//` comment
#             cannot reach it and PowerliftingCore.swift alone would be a guard that cannot fail.
#             BlockCommentImportFixture.swift closes that: a block comment *can* start a line with
#             `import`, and dropping `match_kinds` makes the rule fire on it. Measured, not assumed.

set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "error: swiftlint not found. brew install swiftlint" >&2
    exit 1
fi

# fixture path : rule identifier that must appear
POSITIVE=(
    "scripts/lint-fixtures/Attempt/ColourLiteralFixture.swift:no_color_literals"
    "scripts/lint-fixtures/Attempt/FontSizeFixture.swift:no_raw_font_sizes"
    "scripts/lint-fixtures/Attempt/SpacingFixture.swift:no_magic_spacing"
    "scripts/lint-fixtures/SwiftDataOutsidePersistenceFixture.swift:no_swiftdata_outside_persistence"
    "scripts/lint-fixtures/Packages/PowerliftingCore/FoundationFixture.swift:no_foundation_in_core"
    "scripts/lint-fixtures/Packages/PowerliftingCore/Sources/PlatformImportFixture.swift:no_imports_in_core"
    "scripts/lint-fixtures/Packages/PowerliftingCore/Sources/AttributedImportFixture.swift:no_imports_in_core"
    "scripts/lint-fixtures/Packages/PowerliftingCore/Sources/AttributedImportFixture.swift:no_foundation_in_core"
    "scripts/lint-fixtures/Packages/PowerliftingCore/Sources/MissingDocsFixture.swift:missing_docs"
)

# file : rule identifier that must NOT appear (the file mentions the import in a comment)
NEGATIVE=(
    "Packages/PowerliftingCore/Sources/PowerliftingCore/PowerliftingCore.swift:no_foundation_in_core"
    "Packages/PowerliftingCore/Sources/PowerliftingCore/PowerliftingCore.swift:no_imports_in_core"
    "Packages/Persistence/Sources/Persistence/Persistence.swift:no_swiftdata_outside_persistence"
    "scripts/lint-fixtures/Packages/PowerliftingCore/Sources/BlockCommentImportFixture.swift:no_imports_in_core"
)

failures=0

echo "positive — each fixture must trigger its rule"
for pair in "${POSITIVE[@]}"; do
    file="${pair%:*}"
    rule="${pair##*:}"

    if [[ ! -f "$file" ]]; then
        printf '  FAIL  %-34s fixture is missing: %s\n' "$rule" "$file"
        failures=$((failures + 1))
        continue
    fi

    # swiftlint exits non-zero on a serious violation, which is the expected outcome here.
    output="$(swiftlint lint --no-cache "$file" 2>/dev/null || true)"

    if grep -q "($rule)" <<<"$output"; then
        printf '  ok    %-34s fires\n' "$rule"
    else
        printf '  FAIL  %-34s did NOT fire on %s\n' "$rule" "$file"
        failures=$((failures + 1))
    fi
done

echo
echo "negative — prose mentioning a banned import must not trigger it"
for pair in "${NEGATIVE[@]}"; do
    file="${pair%:*}"
    rule="${pair##*:}"

    if [[ ! -f "$file" ]]; then
        printf '  skip  %-34s %s no longer exists\n' "$rule" "$file"
        continue
    fi

    output="$(swiftlint lint --no-cache "$file" 2>/dev/null || true)"

    if grep -q "($rule)" <<<"$output"; then
        printf '  FAIL  %-34s fired on a comment in %s\n' "$rule" "$file"
        failures=$((failures + 1))
    else
        printf '  ok    %-34s correctly ignores comments in %s\n' "$rule" "$(basename "$file")"
    fi
done

echo
if (( failures > 0 )); then
    echo "$failures rule check(s) failed — the rules are not enforcing what they claim." >&2
    exit 1
fi

# Count distinct rules, not entries: since 2026-08-04 a fixture may be listed against more than one
# rule (AttributedImportFixture triggers two), so ${#POSITIVE[@]} is a check count, not a rule count.
rule_count="$(printf '%s\n' "${POSITIVE[@]}" | sed 's/.*://' | sort -u | wc -l | tr -d ' ')"
echo "all $rule_count rules fire across ${#POSITIVE[@]} checks, and ${#NEGATIVE[@]} comment false-positive guards hold."
