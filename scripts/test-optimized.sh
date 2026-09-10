#!/usr/bin/env bash
#
# G-1.2 / DOD-1.4: run the tests of every package that fetches through SwiftData at -O.
#
#   scripts/test-optimized.sh [package-path ...]     # default: Persistence, RepositoryFakes
#
# WHY. `swift test` and `build-packages.sh --test` build at -Onone, and one class of defect exists
# only under the optimizer: a `#Predicate` built in a generic context captures a key path that the
# optimizer re-instantiates when it specialises the generic, and SwiftData then cannot match it
# against the key paths the `@Model` macro registered. The first fetch dies with
#
#     Fatal error: Couldn't find \ExerciseEntity.<computed 0x…(UUID)> on ExerciseEntity
#
# Measured: a `#Predicate<T> { $0.id == id }` written inside a generic `where T: StoredEntity`
# function passes this package's 264 tests at -Onone and kills the process with that error at -O,
# in the first suite that fetches. `StoredEntity`'s per-type predicate requirements are the
# compile-time half of the guard; this run is the half that sees a fetch site nobody wrote through
# them.
#
# WHAT IT COSTS. A release build of Persistence and what it depends on — about 40 s cold — then the
# same tests in under a second. `Persistence` is the one package that *fetches*, and a package that
# gains a `ModelContext` fetch belongs on the default list below.
#
# `RepositoryFakes` is on the list for a second reason and it is not that it fetches — it holds no
# `ModelContext` at all. Its shared conformance suite drives `PersistenceStack` as one of its two
# subjects, so it is where several of `Persistence`'s predicates are reached from at all: T-17.10's
# `sessions(forProgramRunID:week:)` is exercised there and nowhere in `PersistenceTests`. A suite
# that reaches a fetch belongs here as much as the fetch does.
#
# `-enable-testing` is what lets `@testable import` compile at -O. It does not change what the
# optimizer does to a predicate, which is what keeps this run honest.

set -euo pipefail

cd "$(dirname "$0")/.."

packages=("$@")
if (( ${#packages[@]} == 0 )); then
    packages=(Packages/Persistence Packages/RepositoryFakes)
fi

for package in "${packages[@]}"; do
    echo "==> $package, optimized"
    if ! swift test -c release -Xswiftc -enable-testing --package-path "$package" 2>&1 | tail -3; then
        cat >&2 <<MSG
test-optimized.sh: $package fails at -O. If the unoptimized suite is green, read StoredEntity's
requirements first — a predicate built in a generic context is the usual cause, and the unoptimized
build cannot see it.
MSG
        exit 1
    fi
done

echo "ok — every fetching package passes its tests optimized."
