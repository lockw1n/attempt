#!/usr/bin/env bash
#
# G-3.4's app-target half: every `app.*` key the app target writes exists in its catalogue, and
# every key in the catalogue is written somewhere.
#
# WHY A SCRIPT AND NOT A TEST. Each feature module proves this in its own test target — see
# SettingsTests' "The catalogue and the accessors name exactly the same keys". Attempt.xcodeproj has
# no test target, so the app target is the one place a key has neither a test nor a lint rule behind
# it: `no_literal_ui_strings` deliberately does not scan `Attempt/`, because a literal there is
# CORRECT (`LocalizedStringKey` resolves against `Bundle.main`, the app's own catalogue). That
# exemption is what leaves a mistyped key silent — it compiles, it lints, and it renders
# `app.tab.hom` in the tab bar.
#
# WHAT IT DOES NOT CATCH: a key built by interpolation rather than written as a literal, and a key
# that is spelled correctly but points at the wrong copy. It reads the source, not the running app;
# the pseudolocale pass is still what proves a screen draws from the catalogue.

set -euo pipefail

cd "$(dirname "$0")/.."

CATALOGUE="Attempt/Resources/Localizable.xcstrings"

if [[ ! -f "$CATALOGUE" ]]; then
    echo "error: $CATALOGUE is missing" >&2
    exit 1
fi

# Keys written in the app target. Line comments are stripped first: a key quoted in prose explaining
# the convention is not a use of it, and counting it would let an orphan hide behind its own
# documentation.
referenced="$(
    find Attempt -name '*.swift' -print0 |
        xargs -0 sed 's|//.*||' |
        grep -oE '"app\.[A-Za-z0-9._-]+"' |
        tr -d '"' |
        sort -u
)"

declared="$(
    python3 -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    print("\n".join(sorted(json.load(handle)["strings"])))
' "$CATALOGUE"
)"

failures=0

missing="$(comm -23 <(echo "$referenced") <(echo "$declared"))"
if [[ -n "$missing" ]]; then
    echo "G-3.4: written in the app target but absent from $CATALOGUE —"
    echo "       the user would see the key name itself."
    sed 's/^/  /' <<<"$missing"
    failures=$((failures + 1))
fi

orphaned="$(comm -13 <(echo "$referenced") <(echo "$declared"))"
if [[ -n "$orphaned" ]]; then
    echo "G-3.4: in $CATALOGUE but written nowhere in the app target —"
    echo "       delete the key, or the screen that lost it."
    sed 's/^/  /' <<<"$orphaned"
    failures=$((failures + 1))
fi

# The same convention the module catalogues are held to, checked here by the same three clauses:
# lowercase, dot-separated, at least <module>.<screen>.<element>, and named for its own catalogue.
#
# Over BOTH sets, not just the declared one: a key that breaks the convention breaks it wherever it
# is written, and one written in the source but never declared appears in neither list above if the
# convention check is the only thing that would name it.
while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    # `tr` rather than `${key,,}`: macOS ships bash 3.2, where that expansion is a syntax error.
    lowercased="$(tr '[:upper:]' '[:lower:]' <<<"$key")"
    if [[ "$key" != "app."* ]] || [[ "$key" != "$lowercased" ]] ||
        [[ "$(tr -cd '.' <<<"$key" | wc -c)" -lt 2 ]]; then
        echo "G-3.4: '$key' does not follow <module>.<screen>.<element>, lowercase"
        failures=$((failures + 1))
    fi
done <<<"$(printf '%s\n%s\n' "$referenced" "$declared" | sort -u)"

if ((failures > 0)); then
    echo
    echo "FAILED — $failures problem(s)"
    exit 1
fi

echo "ok — $(wc -l <<<"$declared" | tr -d ' ') app-target keys, each written and each declared"
