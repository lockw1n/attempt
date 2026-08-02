# shellcheck shell=bash
#
# G-6.4: the single definition of the warnings-as-errors flags. SOURCED, never executed.
#
#     source "$(dirname "${BASH_SOURCE[0]}")/swift-strict-flags.sh"
#     swift build --package-path "$pkg" "${SWIFT_STRICT_FLAGS[@]}"
#
# WHY THIS IS NOT IN THE MANIFESTS ANY MORE (T-0.03, 2026-08-02).
#
# Until this date every `Package.swift` carried `.treatAllWarnings(as: .error)`. That stopped
# working the moment the packages were linked into `Attempt.xcodeproj`: Xcode injects
# `-suppress-warnings` into SwiftPM package targets it builds as dependencies, and the compiler
# rejects that together with `-warnings-as-errors`:
#
#     error: Conflicting options '-warnings-as-errors' and '-suppress-warnings'
#            (in target 'PowerliftingCore' from project 'PowerliftingCore')
#
# Overriding SUPPRESS_WARNINGS at project level, at target level, and via an `.xcconfig` were all
# tried and all had no effect — settings inside Attempt.xcodeproj never reach the synthesized
# package projects. Only a command-line setting works, which the Xcode GUI cannot supply, so
# keeping the manifests as they were meant a plain ⌘B could not build the app at all.
#
# The gate therefore moved here. It did NOT weaken: the manifests duplicated `strictSettings`
# once per package, so a fourth package silently missed the gate unless someone remembered to
# copy the block. `build-packages.sh` discovers packages by glob, so a new package is covered the
# moment it exists. `verify-warnings-gate.sh` proves the flags still fail a build on a warning,
# so this is a gate with a test behind it rather than a flag someone hopes is still wired up.
#
# The one thing genuinely lost: a bare `swift build` no longer fails on a warning. Use
# `scripts/build-packages.sh` at the desk, and CI catches it either way on the next push.

SWIFT_STRICT_FLAGS=(-Xswiftc -warnings-as-errors)
