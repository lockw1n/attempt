import Foundation
import os

/// The interval instrument `NFR-1.2` and `NFR-1.6` are measured through on a device.
///
/// **A signpost rather than a test, because on a device there is no test.** An SPM test bundle
/// cannot be hosted on a device destination at all, and the app target has no test target to host
/// one, so every figure those two requirements ask for has to come out of the shipping binary
/// while a lifter drives it. `Instruments`' *os_signpost* instrument reads these; the recipe that
/// records them is `scripts/measure-device.sh`.
///
/// **It ships, and that is the point rather than a concession.** A signpost over a disabled log is
/// a predictable branch and an atomic load; the number the requirement wants is the one the
/// released build produces, and an instrument compiled out of that build measures a different
/// program. `G-5.1` is untouched — `os` is Apple's.
///
/// **The interval is the user-visible one, never the inner call.** `NFR-1.2` budgets the wait
/// between an answer and the row re-reading, which spans a write, a recompute trigger and a reload;
/// marking only the write would report a number nobody experiences.
public struct PerformanceSignpost: Sendable {
    /// The subsystem every interval in this app is filed under.
    ///
    /// **The bundle identifier, and this is its only home** — `Instruments` filters on it, and a
    /// second spelling elsewhere would put half the intervals in a category the recipe does not
    /// look at.
    public static let subsystem = "lockw1n.Attempt"

    /// `NFR-1.2`: an answer on a planned day, from the tap to the row having re-read. Budget 100 ms.
    public static let answer = PerformanceSignpost("answer", category: "NFR-1.2")

    /// `NFR-1.6`: one exercise's records and estimate recomputed. Budget 500 ms, off the main actor.
    public static let recompute = PerformanceSignpost("recompute", category: "NFR-1.6")

    /// `NFR-17.4`: the Train root's read of the week. Asserted to walk no set history; this is the
    /// time that assertion never took.
    public static let week = PerformanceSignpost("week", category: "NFR-17.4")

    /// What Instruments files the interval under — the requirement, so a trace names what it proves.
    private let signposter: OSSignposter

    /// The interval's own name within that category.
    private let name: StaticString

    /// Builds one named interval.
    ///
    /// - Parameters:
    ///   - name: What the interval is called in the trace.
    ///   - category: The requirement it measures, which is what the trace is filtered by.
    private init(_ name: StaticString, category: String) {
        self.name = name
        self.signposter = OSSignposter(subsystem: Self.subsystem, category: category)
    }

    /// Runs `body`, marking its start and end so the elapsed time appears in a trace.
    ///
    /// **The state never leaves this scope**, which is what lets an `async` body be measured at all:
    /// an interval token handed across a suspension would have to be `Sendable`, and keeping the
    /// begin and the end in one function makes the question moot.
    ///
    /// **It inherits the caller's isolation rather than hopping**, which is both correctness and
    /// accuracy: a nonisolated measure would refuse an actor-isolated body outright, and any hop it
    /// introduced would be counted inside the interval as if the work had taken that long.
    ///
    /// - Parameters:
    ///   - isolation: The caller's actor, filled in by the compiler. Never passed by hand.
    ///   - body: The work being measured.
    /// - Returns: Whatever `body` returns.
    /// - Throws: Whatever `body` throws — the interval is closed either way.
    public func measure<T>(
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try await body()
    }
}
