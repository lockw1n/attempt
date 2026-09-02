#!/usr/bin/env bash
#
# Usage:
#   scripts/check-translations.sh             # every catalogue has a complete Ukrainian half
#   scripts/check-translations.sh --self-test # prove each check fires
#
# FR-1.14.1's guard, and it exists because of a cliff T-1.18 measured: once `uk` is one of a
# bundle's localizations, a key with no Ukrainian value renders ITS OWN IDENTIFIER on screen. It
# does not fall back to English. So a later task that adds a key to en.lproj and forgets uk.lproj
# does not ship an English string into a Ukrainian app — it ships `settings.landing.units.title`
# into one, and nothing else in the chain would say so: the module's own tests resolve keys against
# the test process's `en`, SwiftLint reads source rather than resources, and a snapshot pins English.
#
# WHAT IT CHECKS, per catalogue directory that has an en.lproj:
#
#   1  A uk.lproj beside it, holding the same files — both directions. A uk-only file is copy
#      nothing can reach, and the likeliest one is a .stringsdict added because Ukrainian needs a
#      plural where English spells the same key with a plain string.
#   2  The same key set in each file, both directions. A key only uk has is as wrong as one only
#      en has: it is copy the app can never show, and usually a typo in the key.
#   3  No empty Ukrainian value — inside a .stringsdict as well as beside a key. An empty string
#      renders as nothing at all, which reads as a layout bug rather than as a missing translation.
#   4  The same format specifiers, as a multiset with the argument positions dropped, again reaching
#      inside a .stringsdict: a Ukrainian plural form answers to English's `other` for the two
#      categories English does not have. A translation that loses a `%lld` renders the wrong number
#      of arguments, and one that gains a specifier reads uninitialised stack — neither is visible
#      in a diff of two languages side by side, and nine of the counted plural forms live in a
#      .stringsdict, where checks 3 and 4 would otherwise not reach.
#   5  In a .stringsdict, all four Ukrainian plural categories on every variable. English needs
#      `one` and `other`; Ukrainian needs `few` (2–4) and `many` (0, 5–20) as well, and a variable
#      missing one of them silently falls back to `other` — "5 день" rather than "5 днів".
#   6  In a .stringsdict, that the format key names every variable declared and declares every
#      variable it names. A format key naming none renders no count at all, and the plural forms
#      below it are then unreachable however correct they are.
#   7  The app target's String Catalogue: a `uk` unit, translated and non-empty, for every key.
#   8  `uk` in the .pbxproj's knownRegions, without which xcodebuild copies no uk.lproj into the
#      app at all and every check above passes over a translation nobody can reach.
#
# WHAT IT DOES NOT CATCH: a Ukrainian value that is wrong, or that is still the English string.
# Copy is read, not computed. Item 4 is the closest this gets, and it only sees the specifiers.
#
# The parsing is deliberately not `plutil`: this reads the same two text formats on any platform,
# and the self-test below drives the identical code over a scratch tree — every check above, the
# String Catalogue and knownRegions ones included, which is why the latter is a function.

set -euo pipefail

cd "$(dirname "$0")/.."

SELF_TEST=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --self-test) SELF_TEST=1; shift ;;
        -h|--help)
            awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
            exit 0 ;;
        *) echo "check-translations.sh: unknown option '$1'" >&2; exit 64 ;;
    esac
done

CHECKER="$(mktemp)"
trap 'rm -f "$CHECKER"' EXIT

cat > "$CHECKER" <<'PY'
"""Compare every en.lproj under a root with its uk.lproj. Exits 1 on the first problem found."""

import json
import os
import plistlib
import re
import sys

TARGET = "uk"
# Ukrainian's four CLDR plural categories. `other` is unreachable for a whole number and still
# required by the format, so all four are asked for rather than the three that can fire.
CATEGORIES = {"one", "few", "many", "other"}

PAIR = re.compile(r'"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;', re.S)
COMMENT = re.compile(r"/\*.*?\*/", re.S)
# A specifier with its argument position dropped: "%1$@" and "%@" are the same argument in two
# orders, and a translation is free to reorder.
SPECIFIER = re.compile(r"%(?:(\d+)\$)?([-+ #0]*)(\d*)(?:\.\d+)?(hh|h|ll|l|q|z|t|j|L)?([@a-zA-Z%])")
# A .stringsdict entry's format key names its variables as `%#@name@`, optionally positional.
FORMAT_KEY = "NSStringLocalizedFormatKey"
VARIABLE = re.compile(r"%(?:\d+\$)?#@([^@]+)@")

problems = []


def fail(message):
    problems.append(message)


def read_strings(path):
    with open(path, encoding="utf-8") as handle:
        text = COMMENT.sub("", handle.read())
    return {key: value for key, value in PAIR.findall(text)}


def read_plurals(path):
    with open(path, "rb") as handle:
        return plistlib.load(handle)


def specifiers(value):
    found = []
    for _, flags, width, length, kind in SPECIFIER.findall(value):
        if kind == "%":
            continue
        found.append("%" + flags + width + (length or "") + kind)
    return sorted(found)


def compare_text(label, where, source, target):
    """Emptiness and format specifiers — what any one translated string owes its source."""
    if not target.strip():
        fail(f"{label}: {where} has an empty {TARGET} value")
        return
    if specifiers(source) != specifiers(target):
        fail(f"{label}: {where} does not carry the same format specifiers — "
             f"{specifiers(source)} vs {specifiers(target)}")


def plural_forms(variable):
    """A .stringsdict variable's category → string pairs, without its two type keys."""
    return {name: value for name, value in variable.items() if not name.startswith("NSString")}


def compare_plural_entry(label, key, source, target):
    """A .stringsdict value is an entry rather than a string — a format key plus one dict per
    variable — and every string buried in it owes its source exactly what a flat value does."""
    compare_text(label, f"'{key}' {FORMAT_KEY}",
                 source.get(FORMAT_KEY, ""), target.get(FORMAT_KEY, ""))

    declared = {name for name, value in target.items() if isinstance(value, dict)}
    named = set(VARIABLE.findall(target.get(FORMAT_KEY, "")))
    for name in sorted(named - declared):
        fail(f"{label}: '{key}' names variable '{name}' in its format and never declares it")
    for name in sorted(declared - named):
        fail(f"{label}: '{key}' declares variable '{name}' and its format never names it — "
             f"the count it renders is dropped")

    for name in sorted(declared & {n for n, v in source.items() if isinstance(v, dict)}):
        source_forms, target_forms = plural_forms(source[name]), plural_forms(target[name])
        for category, value in sorted(target_forms.items()):
            # `few` and `many` have no English counterpart, so they answer to `other` — the form
            # English uses for every count but one, and the one that carries its specifiers.
            reference = source_forms.get(category, source_forms.get("other", ""))
            compare_text(label, f"'{key}' variable '{name}' form '{category}'", reference, value)


def compare_values(label, source, target):
    """The three checks a pair of tables owes each other: keys, emptiness, specifiers. The last two
    reach into a .stringsdict entry through `compare_plural_entry` rather than stopping at it."""
    missing = sorted(set(source) - set(target))
    if missing:
        fail(f"{label}: no {TARGET} value for {len(missing)} key(s) — each renders its own "
             f"identifier on screen:\n  " + "\n  ".join(missing))
    extra = sorted(set(target) - set(source))
    if extra:
        fail(f"{label}: {len(extra)} {TARGET} key(s) with nothing to translate:\n  "
             + "\n  ".join(extra))
    for key in sorted(set(source) & set(target)):
        if isinstance(source[key], str) and isinstance(target[key], str):
            compare_text(label, f"'{key}'", source[key], target[key])
        elif isinstance(source[key], dict) and isinstance(target[key], dict):
            compare_plural_entry(label, key, source[key], target[key])
        else:
            fail(f"{label}: '{key}' is a {type(target[key]).__name__} in {TARGET} and a "
                 f"{type(source[key]).__name__} in the source")


def check_plural_categories(label, table):
    for key, entry in table.items():
        if not isinstance(entry, dict):
            continue
        for name, variable in entry.items():
            if name == "NSStringLocalizedFormatKey" or not isinstance(variable, dict):
                continue
            given = {n for n in variable if not n.startswith("NSString")}
            if not CATEGORIES <= given:
                fail(f"{label}: '{key}' variable '{name}' is missing the "
                     f"{sorted(CATEGORIES - given)} plural form(s) — a count that falls into one "
                     f"of them silently renders the 'other' form instead")


def check_catalogue_dir(source_dir):
    target_dir = os.path.join(os.path.dirname(source_dir), f"{TARGET}.lproj")
    if not os.path.isdir(target_dir):
        fail(f"{target_dir} is missing — {source_dir} has no {TARGET} translation at all")
        return
    def files_in(directory):
        return {name for name in os.listdir(directory)
                if not name.startswith(".") and os.path.isfile(os.path.join(directory, name))}

    for name in sorted(files_in(target_dir) - files_in(source_dir)):
        fail(f"{os.path.join(target_dir, name)} has no counterpart in {source_dir} — nothing it "
             f"holds can be reached")
    for name in sorted(files_in(source_dir)):
        source = os.path.join(source_dir, name)
        target = os.path.join(target_dir, name)
        if not os.path.isfile(target):
            fail(f"{target} is missing, and {source} exists")
            continue
        label = os.path.relpath(target)
        if name.endswith(".stringsdict"):
            source_table, target_table = read_plurals(source), read_plurals(target)
            compare_values(label, source_table, target_table)
            check_plural_categories(label, target_table)
        else:
            compare_values(label, read_strings(source), read_strings(target))


def check_string_catalogue(path):
    with open(path, encoding="utf-8") as handle:
        catalogue = json.load(handle)
    source_language = catalogue.get("sourceLanguage", "en")
    label = os.path.relpath(path)
    for key, entry in sorted(catalogue.get("strings", {}).items()):
        localizations = entry.get("localizations", {})
        unit = localizations.get(TARGET, {}).get("stringUnit", {})
        value = unit.get("value", "")
        if not value.strip():
            fail(f"{label}: '{key}' has no {TARGET} value — it renders its own identifier")
            continue
        if unit.get("state") != "translated":
            fail(f"{label}: '{key}' is marked '{unit.get('state')}' rather than translated")
        source = localizations.get(source_language, {}).get("stringUnit", {}).get("value", "")
        if specifiers(source) != specifiers(value):
            fail(f"{label}: '{key}' does not carry the same format specifiers — "
                 f"{specifiers(source)} vs {specifiers(value)}")


root = sys.argv[1]
catalogue_dirs, string_catalogues = [], []
for directory, subdirectories, files in os.walk(root):
    subdirectories[:] = [d for d in subdirectories if d not in {".build", ".git"}]
    if os.path.basename(directory) == "en.lproj":
        catalogue_dirs.append(directory)
    string_catalogues += [os.path.join(directory, f) for f in files if f.endswith(".xcstrings")]

if not catalogue_dirs:
    fail(f"no en.lproj found under {root} — this check would pass by looking at nothing")

for directory in sorted(catalogue_dirs):
    check_catalogue_dir(directory)
for path in sorted(string_catalogues):
    check_string_catalogue(path)

if problems:
    print(f"FR-1.14.1: {len(problems)} problem(s) with the {TARGET} translation —")
    for problem in problems:
        print("  " + problem.replace("\n", "\n  "))
    sys.exit(1)

print(f"ok — {len(catalogue_dirs)} catalogue(s) and {len(string_catalogues)} string catalogue(s), "
      f"each complete in {TARGET}")
PY

# knownRegions is the app target's own half, and it is the one thing the checker cannot say about
# itself: with `uk` absent, xcodebuild copies no uk.lproj into the built app and every check the
# checker makes still passes. A function rather than a block so the self-test can drive it too —
# the awk range is what makes a stray `uk` elsewhere in the .pbxproj not count, and a regex that
# nothing exercises is the likeliest of the eight checks to rot.
check_known_regions() {
    local project="$1"
    if awk '/knownRegions = \(/, /\);/' "$project" | grep -qE '^[[:space:]]*uk,?$'; then
        return 0
    fi
    echo "FR-1.14.1: 'uk' is not in knownRegions in $project —"
    echo "           the translation is in the repo and not in the built app."
    return 1
}

if ((SELF_TEST == 0)); then
    python3 "$CHECKER" .
    check_known_regions "Attempt.xcodeproj/project.pbxproj" || exit 1
    echo "ok — uk is a known region of the app target"
    exit 0
fi

# The self-test drives the checker itself — and `check_known_regions` — over scratch fixtures, one
# perturbation at a time. Each case starts from a fixture that passes, so a case that fails proves
# the perturbation is what did it.
SCRATCH="$(mktemp -d)"
trap 'rm -f "$CHECKER"; rm -rf "$SCRATCH"' EXIT

make_tree() {
    local root="$1"
    rm -rf "$root"
    mkdir -p "$root/Resources/en.lproj" "$root/Resources/uk.lproj"
    printf '"m.s.a" = "One";\n"m.s.b %%lld" = "Two %%lld";\n' >"$root/Resources/en.lproj/Localizable.strings"
    printf '"m.s.a" = "Один";\n"m.s.b %%lld" = "Два %%lld";\n' >"$root/Resources/uk.lproj/Localizable.strings"
    for locale in en uk; do
        cat >"$root/Resources/$locale.lproj/Localizable.stringsdict" <<'DICT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>m.s.c %lld</key>
	<dict>
		<key>NSStringLocalizedFormatKey</key>
		<string>%#@n@</string>
		<key>n</key>
		<dict>
			<key>NSStringFormatSpecTypeKey</key>
			<string>NSStringPluralRuleType</string>
			<key>NSStringFormatValueTypeKey</key>
			<string>lld</string>
			<key>one</key>
			<string>%lld a</string>
			<key>few</key>
			<string>%lld b</string>
			<key>many</key>
			<string>%lld c</string>
			<key>other</key>
			<string>%lld d</string>
		</dict>
	</dict>
</dict>
</plist>
DICT
    done
    # Item 7's half. The app target carries its copy as a String Catalogue rather than a pair of
    # .lproj tables, so it is a second format reading the same rule.
    cat >"$root/Resources/Localizable.xcstrings" <<'CATALOGUE'
{
  "sourceLanguage" : "en",
  "strings" : {
    "m.tab.home %@" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Home %@" } },
        "uk" : { "stringUnit" : { "state" : "translated", "value" : "Головна %@" } }
      }
    }
  },
  "version" : "1.0"
}
CATALOGUE
}

# The .pbxproj fixture is only the knownRegions block: that is all the awk range reads, and a whole
# project file here would say nothing more while hiding which line is the one under test.
make_project() {
    local path="$1" extra="$2"
    {
        printf '\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n'
        if [[ -n "$extra" ]]; then
            printf '\t\t\t\t%s,\n' "$extra"
        fi
        printf '\t\t\t);\n'
    } >"$path"
}

failures=0

expect() {
    local wanted="$1" what="$2" root="$SCRATCH/case"
    if python3 "$CHECKER" "$root" >"$SCRATCH/out" 2>&1; then
        local got=pass
    else
        local got=fail
    fi
    if [[ "$got" != "$wanted" ]]; then
        echo "self-test: expected $wanted, got $got — $what"
        sed 's/^/    /' "$SCRATCH/out"
        failures=$((failures + 1))
    fi
}

expect_regions() {
    local wanted="$1" what="$2"
    if check_known_regions "$SCRATCH/project.pbxproj" >"$SCRATCH/out" 2>&1; then
        local got=pass
    else
        local got=fail
    fi
    if [[ "$got" != "$wanted" ]]; then
        echo "self-test: expected $wanted, got $got — $what"
        sed 's/^/    /' "$SCRATCH/out"
        failures=$((failures + 1))
    fi
}

make_tree "$SCRATCH/case"
expect pass "a complete translation"

make_tree "$SCRATCH/case"
rm -rf "$SCRATCH/case/Resources/uk.lproj"
expect fail "no uk.lproj at all"

make_tree "$SCRATCH/case"
printf '"m.s.a" = "Один";\n' >"$SCRATCH/case/Resources/uk.lproj/Localizable.strings"
expect fail "a key with no Ukrainian value"

make_tree "$SCRATCH/case"
printf '"m.s.a" = "Один";\n"m.s.b %%lld" = "Два %%lld";\n"m.s.z" = "Зайве";\n' \
    >"$SCRATCH/case/Resources/uk.lproj/Localizable.strings"
expect fail "a Ukrainian key with nothing behind it"

make_tree "$SCRATCH/case"
printf '"m.s.a" = "";\n"m.s.b %%lld" = "Два %%lld";\n' >"$SCRATCH/case/Resources/uk.lproj/Localizable.strings"
expect fail "an empty Ukrainian value"

make_tree "$SCRATCH/case"
printf '"m.s.a" = "Один";\n"m.s.b %%lld" = "Два";\n' >"$SCRATCH/case/Resources/uk.lproj/Localizable.strings"
expect fail "a translation that dropped a format specifier"

make_tree "$SCRATCH/case"
python3 - "$SCRATCH/case/Resources/uk.lproj/Localizable.stringsdict" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, "rb") as handle:
    table = plistlib.load(handle)
del table["m.s.c %lld"]["n"]["few"]
with open(path, "wb") as handle:
    plistlib.dump(table, handle)
PY
expect fail "a plural variable with no 'few' form"

make_tree "$SCRATCH/case"
python3 - "$SCRATCH/case/Resources/uk.lproj/Localizable.stringsdict" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, "rb") as handle:
    table = plistlib.load(handle)
table["m.s.c %lld"]["n"]["many"] = table["m.s.c %lld"]["n"]["many"].replace("%lld", "")
with open(path, "wb") as handle:
    plistlib.dump(table, handle)
PY
expect fail "a plural form that dropped its %lld"

make_tree "$SCRATCH/case"
python3 - "$SCRATCH/case/Resources/uk.lproj/Localizable.stringsdict" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, "rb") as handle:
    table = plistlib.load(handle)
table["m.s.c %lld"]["n"]["few"] = ""
with open(path, "wb") as handle:
    plistlib.dump(table, handle)
PY
expect fail "an empty plural form"

make_tree "$SCRATCH/case"
python3 - "$SCRATCH/case/Resources/uk.lproj/Localizable.stringsdict" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, "rb") as handle:
    table = plistlib.load(handle)
table["m.s.c %lld"]["NSStringLocalizedFormatKey"] = "nothing"
with open(path, "wb") as handle:
    plistlib.dump(table, handle)
PY
expect fail "a format key that names no variable"

make_tree "$SCRATCH/case"
printf '"m.s.d" = "Лише тут";\n' >"$SCRATCH/case/Resources/uk.lproj/Extra.strings"
expect fail "a file only uk.lproj has"

make_tree "$SCRATCH/case"
python3 - "$SCRATCH/case/Resources/Localizable.xcstrings" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as handle:
    catalogue = json.load(handle)
del catalogue["strings"]["m.tab.home %@"]["localizations"]["uk"]
with open(path, "w") as handle:
    json.dump(catalogue, handle, ensure_ascii=False)
PY
expect fail "a String Catalogue key with no uk unit"

make_tree "$SCRATCH/case"
python3 - "$SCRATCH/case/Resources/Localizable.xcstrings" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as handle:
    catalogue = json.load(handle)
catalogue["strings"]["m.tab.home %@"]["localizations"]["uk"]["stringUnit"]["state"] = "needs_review"
with open(path, "w") as handle:
    json.dump(catalogue, handle, ensure_ascii=False)
PY
expect fail "a String Catalogue unit still marked needs_review"

make_tree "$SCRATCH/case"
python3 - "$SCRATCH/case/Resources/Localizable.xcstrings" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as handle:
    catalogue = json.load(handle)
unit = catalogue["strings"]["m.tab.home %@"]["localizations"]["uk"]["stringUnit"]
unit["value"] = unit["value"].replace(" %@", "")
with open(path, "w") as handle:
    json.dump(catalogue, handle, ensure_ascii=False)
PY
expect fail "a String Catalogue translation that dropped its %@"

make_project "$SCRATCH/project.pbxproj" uk
expect_regions pass "uk among the known regions"

make_project "$SCRATCH/project.pbxproj" ""
expect_regions fail "uk missing from the known regions"

# The awk range is the whole point of item 8: `uk` anywhere else in the file is not the app's
# region, and a bare grep over the .pbxproj would call this one green.
make_project "$SCRATCH/project.pbxproj" ""
printf '\t\t\t\tuk,\n' >>"$SCRATCH/project.pbxproj"
expect_regions fail "uk present but outside the knownRegions block"

if ((failures > 0)); then
    echo "FAILED — $failures self-test case(s)"
    exit 1
fi

echo "ok — every check fires"
