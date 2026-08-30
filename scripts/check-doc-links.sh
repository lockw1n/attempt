#!/usr/bin/env bash
#
# DocC symbol-link validation for the local Swift packages (TR-1.15).
#
#   scripts/check-doc-links.sh                          # the gate: every module, every link
#   scripts/check-doc-links.sh Packages/Persistence     # report only that package's links
#   scripts/check-doc-links.sh --self-test              # prove the gate can fail
#
# `missing_docs` gates whether a doc comment exists and check-doc-units.sh gates whether it names
# its unit; this gates whether the ``symbol`` links inside it resolve to anything. An unresolved
# link compiles clean, lints clean, and renders as plain text — nothing else in the toolchain
# notices, and two shipped that way in Phase 0.
#
# HOW, and why not the DocC plugin. `swift package dump-symbol-graph` is built into SwiftPM, so
# the symbol graphs cost no package dependency and no manifest edit — swift-docc-plugin would have
# to be added to all eighteen manifests, including the two the Linux job builds. `docc` itself
# ships with the toolchain. Every module goes into ONE `docc convert`, which is both faster than
# per-package runs and the only arrangement in which a cross-module link can resolve at all.
#
# AND NOT the compiler's own `-emit-symbol-graph` under a plain `swift build`, which was tried
# here, reads better — it never builds a test target — and is disqualified: two runs over one
# unchanged tree reported 8 unresolved links and then 16, because a package's dependencies emit
# graphs only when that invocation happens to compile them. `dump-symbol-graph` extracts from the
# built module every time and gave byte-identical output across runs. A gate that reports a
# different set of failures each time it runs is worse than a gate with a known blind spot, and
# this one has a known blind spot: extraction reads the built module, so a link in the doc comment
# of a `private` or `internal` member is not in the graph and is never checked, whatever
# `--minimum-access-level` says. The compiler's own emission sees those; nothing else does.
#
# A TARGET THIS GATE DISCARDS MUST NOT BE ABLE TO FAIL IT. `dump-symbol-graph` extracts per target,
# test targets included, and CI died on `AppNavigationPackageTests` after every first-party module
# came out clean — not reproducible at the desk on the same Xcode 26.6, cold tree or warm. The
# extraction failure is therefore tolerated and the graphs are checked instead: every module under
# a package's Sources/ must have produced one, and a missing graph fails loudly with the extraction
# log rather than being read as "nothing to report".
#
# A NAMED PACKAGE NARROWS THE REPORT, NOT THE RUN. Every package is dumped either way. Restricting
# the set of graphs is precisely what makes a cross-module link unresolvable, so a run over one
# package would report this tree's ~60 module-qualified links as broken — measured: 14 of them in
# Features/Settings alone. The argument selects whose diagnostics are printed and counted, and the
# rest are tallied as "outside the requested scope".
#
# ACCESS LEVEL IS `private`, deliberately. DocC can only resolve a link to a symbol that is in a
# graph, so at the default (`public`) every link to an internal type — and every ``CodingKeys`` —
# reads as broken: 100 failures at `public` and 117 at `internal` against 81 at `private`, on the
# tree that first ran this. The gate is about whether a link names something real, not about what
# a published documentation archive would contain.
#
# WHAT COUNTS AS BROKEN: every DocC diagnostic except the one pattern in IGNORED below. Not a
# list of link-shaped diagnostics to fail on — the inverse — so a diagnostic this script has never
# seen fails loudly instead of being silently skipped by a filter that does not recognise it.
# Parameter documentation is the sole exemption, and it is scope rather than taste: `NFR-0.3`
# covers units and ranges, nothing requires a `- Parameter` per argument, and the 1.5:1 doc-ratio
# ceiling in check-doc-ratio.sh actively argues against adding ~12 of them.
#
# THE THREE FIXES for what it reports, since none is guessable from the message:
#   - a link to a symbol in ANOTHER first-party module needs the module name in the path —
#     ``PowerliftingCore/RPETable/standard``, not ``RPETable/standard``. DocC does not search
#     sibling modules.
#   - a link to a symbol this build does not contain (Swift, Foundation, SwiftUI — `Hashable`,
#     `Calendar`, `allCases`) cannot be made to resolve, and belongs in single backticks. It was
#     already rendering as plain text; the backticks just stop claiming otherwise.
#   - a link to one of OUR OWN methods in an extension on someone else's type — `saveStamped(at:)`
#     on SwiftData's `ModelContext`, `sortedDeterministically(by:descending:)` on `Sequence` — is
#     first-party and still has no page here: these graphs carry no extension blocks, so docc drops
#     those members and there is no path to write. Single backticks, and keep the extended type in
#     the text so the reader can still find it. `dump-symbol-graph` can emit extension blocks;
#     whether that earns an "Extended Modules" page per module for three links has not been argued,
#     and no requirement asks.
#
# TWO KNOWN LIMITS, so a green run is not overread.
#
# The app target is not covered. `Attempt/` is not a package, so it has no symbol graph here and
# `xcodebuild docbuild` would be a second mechanism for a target `missing_docs` already exempts. A
# link in an app-target doc comment is checked by nothing.
#
# Platform-conditional code is not covered either. Graphs are dumped for the host, macOS, so
# anything behind `#if os(iOS)` compiles to nothing and contributes no symbols: DesignSystem's
# SnapshotTesting module is gated that way in full and yields an empty graph, its doc comments read
# by nothing here. It carries no ``symbol`` links today and neither does any other gated block in
# the tree, which is what keeps this cheap rather than a second dump per platform.
#
# Two globs, one per level, for the reason build-packages.sh gives: the feature modules sit at
# Packages/Features/<Name>/ and a single `Packages/*/Package.swift` misses all five silently.
#
# Requires python3 (present on macOS with the Xcode command line tools). Runs in the lint job.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/swift-strict-flags.sh"

SELF_TEST=0
PACKAGES=()
# The packages whose diagnostics are reported. Empty means all of them; see the header.
REPORT_SCOPE=()

usage() {
    # The header block above, minus the shebang, up to the first blank/non-comment line.
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --self-test) SELF_TEST=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        -*) echo "check-doc-links.sh: unknown option '$1'" >&2; exit 64 ;;
        *) PACKAGES+=("$1"); shift ;;
    esac
done

cd "$REPO_ROOT"

# The given packages' own library targets — the first-party set. It is both the filter and the
# checklist: a symbol graph whose module is not in it is dropped — a run also produces
# `<Package>PackageTests` and, where a test target depends on one, a third party's (SnapshotTesting),
# neither being surface this requirement is about — and a module in it that produced no graph fails
# the run.
#
# Read from the manifest and not from the Sources/ directory names, because the two disagree where
# it matters: an executable target has a directory like any other and `dump-symbol-graph` emits
# nothing for it, so a checklist built from directories demands a graph that never exists
# (`HarnessCommand`, measured).
first_party_modules() {
    local pkg
    for pkg in "$@"; do
        swift package --package-path "$pkg" describe --type json 2>/dev/null \
            | python3 -c 'import json, sys
for target in json.load(sys.stdin)["targets"]:
    if target.get("type") == "library":
        print(target["name"])'
    done | sort -u
}

# Dump every package's graphs, collect the first-party ones into $1, and run docc over the lot.
# Prints the diagnostics report; returns non-zero when the gate fails.
check_tree() {
    local graph_dir="$1"; shift
    local packages=("$@")
    local pkg manifest module base

    if [[ ${#packages[@]} -eq 0 ]]; then
        for manifest in Packages/*/Package.swift Packages/*/*/Package.swift; do
            [[ -f "$manifest" ]] || continue
            packages+=("$(dirname "$manifest")")
        done
    fi
    if [[ ${#packages[@]} -eq 0 ]]; then
        echo "check-doc-links.sh: no packages found under Packages/" >&2
        return 66
    fi

    for pkg in "${packages[@]}"; do
        [[ -f "$pkg/Package.swift" ]] || { echo "check-doc-links.sh: no package at $pkg" >&2; return 66; }
    done

    local prefix
    for prefix in "${REPORT_SCOPE[@]+"${REPORT_SCOPE[@]}"}"; do
        [[ -f "$prefix/Package.swift" ]] || { echo "check-doc-links.sh: no package at $prefix" >&2; return 66; }
    done

    local allowed
    allowed="$(first_party_modules "${packages[@]}")"
    if [[ -z "$allowed" ]]; then
        echo "check-doc-links.sh: no module directories under the given packages' Sources/" >&2
        return 66
    fi

    mkdir -p "$graph_dir"
    local dump_log module
    dump_log="$(mktemp)"
    for pkg in "${packages[@]}"; do
        # Stale graphs from an earlier run would validate a module that no longer exists.
        rm -rf "$pkg"/.build/*/symbolgraph
        echo "==> symbol graph $pkg"
        # Failure tolerated here and judged below — see the header. A test target's extraction
        # failing says nothing about the modules this gate checks.
        swift package --package-path "$pkg" "${SWIFT_STRICT_FLAGS[@]}" \
            dump-symbol-graph --minimum-access-level private >"$dump_log" 2>&1 || true

        while IFS= read -r graph; do
            base="$(basename "$graph")"
            module="${base%%.symbols.json}"   # `Module` or `Module@Extended`
            module="${module%%@*}"
            grep -qx "$module" <<<"$allowed" || continue
            cp "$graph" "$graph_dir/$base"
        done < <(find "$pkg/.build" -path '*/symbolgraph/*.symbols.json')

        for module in $(first_party_modules "$pkg"); do
            [[ -f "$graph_dir/$module.symbols.json" ]] && continue
            echo "check-doc-links.sh: no symbol graph for $module — $pkg produced none" >&2
            tail -40 "$dump_log" >&2
            rm -f "$dump_log"
            return 70
        done
    done
    rm -f "$dump_log"

    local count
    count="$(find "$graph_dir" -name '*.symbols.json' | wc -l | tr -d ' ')"
    if [[ "$count" -eq 0 ]]; then
        echo "check-doc-links.sh: no first-party symbol graphs collected — nothing was checked" >&2
        return 66
    fi
    echo
    echo "docc: $count first-party symbol graph(s) from ${#packages[@]} package(s)"

    local work diagnostics log
    work="$(mktemp -d)"
    diagnostics="$work/diagnostics.json"
    log="$work/docc.log"
    if ! xcrun docc convert \
        --additional-symbol-graph-dir "$graph_dir" \
        --output-dir "$work/archive" \
        --fallback-display-name Attempt \
        --fallback-bundle-identifier com.attempt.doc-links \
        --diagnostics-file "$diagnostics" >"$log" 2>&1
    then
        echo "check-doc-links.sh: docc failed" >&2
        tail -30 "$log" >&2
        rm -rf "$work"
        return 70
    fi

    local status=0 scope
    scope="$(printf '%s\n' "${REPORT_SCOPE[@]+"${REPORT_SCOPE[@]}"}")"
    DIAGNOSTICS="$diagnostics" REPORT_UNDER="$scope" python3 - <<'PY' || status=$?
import json
import os
import pathlib
import sys

# The only diagnostic this gate does not fail on. Anything else — including a kind DocC has not
# emitted here yet — is reported and fails, so the exemption is a decision rather than a gap.
IGNORED = ("is missing documentation",)

data = json.loads(pathlib.Path(os.environ["DIAGNOSTICS"]).read_text())
diagnostics = data.get("diagnostics", [])

CWD = pathlib.Path.cwd()


def repo_relative(path):
    if not path:
        return ""
    try:
        return str(pathlib.Path(path).resolve().relative_to(CWD))
    except ValueError:
        return path


# Which packages' diagnostics to report. Every module was checked either way — narrowing the run
# instead would break the cross-module links this gate exists to keep working.
scope = [repo_relative(entry) for entry in os.environ.get("REPORT_UNDER", "").split("\n") if entry]

failures = []
ignored_parameters = ignored_synthesised = out_of_scope = 0
for item in diagnostics:
    summary = item.get("summary", "")
    if any(pattern in summary for pattern in IGNORED):
        ignored_parameters += 1
        continue
    source = item.get("source", "")
    if source.startswith("in-memory-data:"):
        # DocC synthesises a landing page when a module has no documentation catalogue, then warns
        # that it is empty. No file in the tree corresponds to it and no doc comment can fix it.
        ignored_synthesised += 1
        continue
    source = repo_relative(source.removeprefix("file://").removeprefix("file:")) or "<no source>"
    if scope and not any(source == p or source.startswith(p + "/") for p in scope):
        out_of_scope += 1
        continue
    line = item.get("range", {}).get("start", {}).get("line", 0)
    failures.append((source, line, item.get("severity", "warning"), summary))

for source, line, severity, summary in sorted(failures):
    print(f"  {source}:{line}: {severity}: {summary}")

print()
print(
    f"docc diagnostics: {len(failures)} unresolved link(s); ignored "
    f"{ignored_parameters} parameter documentation, {ignored_synthesised} synthesised page"
    + (f", {out_of_scope} outside the requested scope" if scope else "")
)

if failures:
    print(
        "\nA ``symbol`` link that resolves to nothing renders as plain text and compiles clean.\n"
        "  - another module's symbol needs the module in the path: ``PowerliftingCore/Weight``\n"
        "  - a symbol outside these packages (Swift, Foundation, SwiftUI) cannot resolve at all,\n"
        "    and belongs in single backticks: `Hashable`\n"
        "See TR-1.15, and this script's header for the rest.",
        file=sys.stderr,
    )
    sys.exit(1)
PY

    rm -rf "$work"
    return "$status"
}

# Fifteen assertions over five fixture packages: the gate passing where it should, failing where
# it should, each of the two scope decisions above — a doc comment in a *test* target is out of
# scope, a missing `- Parameter` is exempted rather than merely unreported — the cross-module
# rule that the majority of this repo's links now depend on. A gate nobody has watched fail is
# decoration, and one that cannot pass is worse.
#
# CrossBase/CrossUser carry the two halves a single-module fixture cannot reach: qualifying a link
# is what makes it resolve, and it resolves only while every module is in the one docc run. Without
# them, running docc per package — or losing a sibling from the graph set — leaves every assertion
# here green while sixty real links break.
self_test() {
    local fixtures="$REPO_ROOT/scripts/lint-fixtures/doc-links"
    local work out status failed=0

    run_case() {
        local name="$1" expected_status="$2" expected_text="$3"; shift 3
        work="$(mktemp -d)"
        set +e
        out="$(check_tree "$work" "$@" 2>&1)"
        status=$?
        set -e
        rm -rf "$work"
        if [[ "$status" -ne "$expected_status" ]]; then
            echo "FAIL  $name: expected exit $expected_status, got $status"
            echo "$out" | sed 's/^/        /'
            failed=1
        elif ! grep -q -- "$expected_text" <<<"$out"; then
            echo "FAIL  $name: expected output matching '$expected_text'"
            echo "$out" | sed 's/^/        /'
            failed=1
        else
            echo "ok    $name"
        fi
    }

    run_case "a clean package passes"                    0 "0 unresolved link(s)"   "$fixtures/CleanLinks"
    run_case "  ... and its parameter warning is exempt" 0 "1 parameter documentation" "$fixtures/CleanLinks"
    run_case "  ... and its test target is out of scope" 0 "1 first-party symbol"   "$fixtures/CleanLinks"
    run_case "a broken symbol link fails"                1 "1 unresolved link(s)"   "$fixtures/BrokenLinks"
    run_case "  ... naming the file it is in"            1 "BrokenLinks.swift"      "$fixtures/BrokenLinks"
    run_case "  ... and the symbol that is missing"      1 "NoSuchSymbol"           "$fixtures/BrokenLinks"
    run_case "  ... and how to fix it"                   1 "single backticks"       "$fixtures/BrokenLinks"
    run_case "a path with no package is an error"       66 "no package at"          "$fixtures/NotAPackage"
    run_case "both fixtures together still fail"         1 "1 unresolved link(s)"   "$fixtures/CleanLinks" "$fixtures/BrokenLinks"

    run_case "a cross-module link needs its module named" 1 "1 unresolved link(s)"  "$fixtures/CrossBase" "$fixtures/CrossUser"
    run_case "  ... and it is the bare spelling that fails" 1 "Bare.swift"          "$fixtures/CrossBase" "$fixtures/CrossUser"
    run_case "  ... and qualifying needs the other graph"  1 "2 unresolved link(s)" "$fixtures/CrossUser"

    # The restrict mode: every module is still checked, and one package's failure is reported.
    REPORT_SCOPE=("$fixtures/CleanLinks")
    run_case "a report scope hides another package"      0 "0 unresolved link(s)"   "$fixtures/CleanLinks" "$fixtures/BrokenLinks"
    run_case "  ... and says how many it hid"            0 "1 outside the requested scope" "$fixtures/CleanLinks" "$fixtures/BrokenLinks"
    REPORT_SCOPE=()

    # The other half of tolerating a failed extraction: a module that produced no graph is a loud
    # failure, not a clean run with nothing to report.
    run_case "a module with no graph is an error"       70 "no symbol graph for BrokenBuild" "$fixtures/BrokenBuild"

    if (( failed )); then
        echo
        echo "check-doc-links.sh --self-test: FAILED" >&2
        return 1
    fi
    echo
    echo "check-doc-links.sh --self-test: 15 assertions passed."
}

if (( SELF_TEST )); then
    self_test
    exit $?
fi

GRAPHS="$(mktemp -d)"
trap 'rm -rf "$GRAPHS"' EXIT
# A named package narrows the report and not the run: check_tree with no packages dumps every one
# of them, which is the only arrangement in which a cross-module link resolves at all.
REPORT_SCOPE=("${PACKAGES[@]+"${PACKAGES[@]}"}")
check_tree "$GRAPHS"
