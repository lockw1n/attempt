// FIXTURE — must trigger `no_imports_in_core` (NFR-0.2, T-0.14).
//
// `no_foundation_in_core` does NOT catch this file: its regex matches only
// `Foundation|FoundationEssentials|FoundationNetworking`, and `Darwin` is none of them. That was
// measured on 2026-08-04 while resolving T-0.14's `pow`/`exp` blocker — the conditional import
// below compiles clean, passes `swiftlint --strict`, and passes the Linux build via the `Glibc`
// branch, so `NFR-0.2` could have been violated with an entirely green CI. `no_imports_in_core`
// exists to close that, and it bans every import rather than a list of module names, because the
// next platform module is not knowable in advance.
//
// The `Packages/PowerliftingCore/Sources/` path segment is load-bearing: the rule is scoped to it,
// and deliberately does not cover Tests/, which needs `import Testing`.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct PlatformImportFixture {
    let placeholder = 0
}
