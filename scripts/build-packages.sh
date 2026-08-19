#!/usr/bin/env bash
#
# G-6.4: build every local package with warnings treated as errors.
#
#   scripts/build-packages.sh                              # build all packages
#   scripts/build-packages.sh --test                       # build, and test those that have tests
#   scripts/build-packages.sh --test Packages/PowerliftingCore   # restrict to given packages
#
# This is the warnings gate. It replaced `.treatAllWarnings(as: .error)` in the manifests — the
# reasoning is in swift-strict-flags.sh, read that before changing anything here.
#
# Packages are DISCOVERED BY GLOB, not listed. That is the point: adding `Packages/Whatever/`
# puts it under the gate with no one having to remember. Do not replace the glob with a hard-coded
# list — the old manifest approach failed exactly there, by requiring the settings block to be
# copied into each new Package.swift by hand.
#
# TWO GLOBS, ONE PER LEVEL. The five feature modules (TR-1.3) live at Packages/Features/<Name>/,
# a level deeper than everything else, because .swiftlint.yml's G-7.7 rules are scoped to that
# path — the argument is in Packages/Features/ExerciseLibrary/Package.swift. A single
# `Packages/*/Package.swift` misses all five silently: the gate stays green while nothing under
# Features/ is built with warnings as errors. An unmatched glob expands to itself and is skipped
# by the `-f` test below, so a level with no packages in it costs nothing.
#
# `swift test` is skipped for packages with no `Tests/` directory, which is why they still need the
# explicit `swift build` above it: a package with no tests is otherwise never compiled by anything,
# and its warnings would be enforced on nobody. DesignSystem was the standing example until T-1.02
# gave it one; the skip path is still live for the next package that lands without tests.

set -euo pipefail

cd "$(dirname "$0")/.."
source "$(dirname "$0")/swift-strict-flags.sh"

RUN_TESTS=0
PACKAGES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --test) RUN_TESTS=1; shift ;;
        -h|--help)
            awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
            exit 0 ;;
        -*) echo "build-packages.sh: unknown option '$1'" >&2; exit 64 ;;
        *) PACKAGES+=("$1"); shift ;;
    esac
done

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
    for manifest in Packages/*/Package.swift Packages/*/*/Package.swift; do
        [[ -f "$manifest" ]] || continue
        PACKAGES+=("$(dirname "$manifest")")
    done
fi

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
    echo "build-packages.sh: no packages found under Packages/" >&2
    exit 66
fi

echo "warnings-as-errors flags: ${SWIFT_STRICT_FLAGS[*]}"
echo

for pkg in "${PACKAGES[@]}"; do
    [[ -f "$pkg/Package.swift" ]] || { echo "build-packages.sh: no package at $pkg" >&2; exit 66; }

    echo "==> build $pkg"
    swift build --package-path "$pkg" "${SWIFT_STRICT_FLAGS[@]}"

    if (( RUN_TESTS )); then
        if [[ -d "$pkg/Tests" ]]; then
            echo "==> test $pkg"
            swift test --package-path "$pkg" "${SWIFT_STRICT_FLAGS[@]}"
        else
            echo "==> test $pkg — skipped, no Tests/ directory"
        fi
    fi
    echo
done

echo "all ${#PACKAGES[@]} package(s) built with warnings as errors."
