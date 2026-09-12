import Foundation
import RepositoryInterface
import Testing

@testable import Attempt

/// What the sync indicator says, and when it is allowed to say it (`FR-1.12.2`).
///
/// **The suite `T-1.71` could not write.** `SyncSnapshotTests` renders each `SyncStatus` against a
/// screen with no control behind it, so it pins how a status *draws* and can say nothing about which
/// status a real launch would hold. Every defect `T-1.86` met was in the second half: the status was
/// well drawn and untrue.
///
/// **Two claims, and they are the two halves of one sentence.** An attempt that finishes before any
/// screen exists must still be in the status that screen is handed — CloudKit's notification reaches
/// only observers alive when it is posted, so a control that started listening inside
/// `statusUpdates()` heard nothing that happened first. And the last success must outlive the
/// process, because `FR-1.12.2` asks for the *last successful sync* and not for the last one this
/// launch witnessed.
///
/// **`UserDefaults` is the thing under test here, so each test gets its own suite name.** The
/// shipped control reads `.standard`, which is process-wide and is what
/// `LaunchSequenceTests.SyncPreferenceGuard` exists to protect; a scratch domain is both faster and
/// the only way these can run in parallel.
@Suite("Sync status reporting (FR-1.12.2)")
struct SyncStatusReportingTests {
    /// A domain nothing else reads, and the handle this test reads it through.
    ///
    /// **The name is what crosses into the control, never this object** — `UserDefaults` is not
    /// `Sendable`, which is the whole reason ``Attempt/AppSyncControl`` takes a name.
    ///
    /// - Returns: The domain's name, and a handle on it.
    private func scratchDomain() throws -> (name: String, defaults: UserDefaults) {
        let name = "sync-status-tests.\(UUID().uuidString)"
        return (name, try #require(UserDefaults(suiteName: name)))
    }

    /// A control fed from a stream the test owns, plus the hand that writes to it.
    ///
    /// - Parameters:
    ///   - name: The preference domain the control opens.
    ///   - isRunning: Whether this launch mirrors.
    /// - Returns: The control, and the continuation its events arrive on.
    private func makeControl(
        in name: String,
        isRunning: Bool = true
    ) -> (AppSyncControl, AsyncStream<SyncEvent>.Continuation) {
        let (stream, continuation) = AsyncStream<SyncEvent>.makeStream()
        let control = AppSyncControl(
            defaultsSuiteName: name,
            isRunning: isRunning,
            events: { stream })
        return (control, continuation)
    }

    /// Waits for the control's status to satisfy `condition`, rather than for a duration.
    ///
    /// **A poll rather than a sleep**, because the fold happens on the actor and the test posts from
    /// outside it: what is being waited for is one hop, and a fixed sleep would either be flaky or
    /// slow. It gives up rather than hanging, so a broken fold fails the test that asked.
    ///
    /// - Parameters:
    ///   - control: The control to read.
    ///   - condition: What the status has to satisfy.
    /// - Returns: The satisfying status, or `nil` if it never arrived.
    private func awaitStatus(
        on control: AppSyncControl,
        until condition: @Sendable (SyncStatus) -> Bool
    ) async -> SyncStatus? {
        for _ in 0..<500 {
            let status = await control.status
            if condition(status) { return status }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return nil
    }

    @Test("An attempt that finishes before any screen opens is in the first status the screen gets")
    func foldsAttemptsMadeBeforeAnyoneIsWatching() async throws {
        let (name, defaults) = try scratchDomain()
        defer { defaults.removePersistentDomain(forName: name) }

        let (control, events) = makeControl(in: name)
        let succeededAt = Date(timeIntervalSince1970: 1_757_000_000)
        // NOTHING IS FOLLOWING YET, which is the whole point: this is the import that lands while
        // the lifter is on the Train tab.
        events.yield(
            SyncEvent(
                activity: .download,
                startDate: succeededAt.addingTimeInterval(-3),
                endDate: succeededAt,
                succeeded: true))

        let settled = try #require(
            await awaitStatus(on: control) { $0.lastSucceededAt != nil },
            "the attempt was never folded — the control is only listening while a screen is open")

        #expect(settled.phase == .idle)
        #expect(settled.lastSucceededAt == succeededAt)

        // And the screen, opening afterwards, is handed it rather than starting from nothing.
        var first: SyncStatus?
        for await status in control.statusUpdates() {
            first = status
            break
        }
        #expect(first?.lastSucceededAt == succeededAt)
    }

    @Test("The last successful sync survives the process it happened in")
    func lastSuccessOutlivesTheLaunch() async throws {
        let (name, defaults) = try scratchDomain()
        defer { defaults.removePersistentDomain(forName: name) }

        let succeededAt = Date(timeIntervalSince1970: 1_757_000_500)
        let (first, events) = makeControl(in: name)
        events.yield(
            SyncEvent(
                activity: .upload,
                startDate: succeededAt.addingTimeInterval(-1),
                endDate: succeededAt,
                succeeded: true))
        _ = try #require(await awaitStatus(on: first) { $0.lastSucceededAt != nil })

        // A SECOND CONTROL OVER THE SAME DEVICE, which is what the next launch is. Anchored to the
        // literal rather than to `first.lastSucceededAt`: two `nil`s compare equal, and this test's
        // whole claim is that neither side is one.
        let (next, _) = makeControl(in: name)
        let reopened = await next.status
        #expect(reopened.lastSucceededAt == succeededAt)
        #expect(reopened.phase == .idle)
    }

    @Test("A failure after a success says when it last worked, not that it never has")
    func failureKeepsTheLastGoodTime() async throws {
        let (name, defaults) = try scratchDomain()
        defer { defaults.removePersistentDomain(forName: name) }

        let succeededAt = Date(timeIntervalSince1970: 1_757_001_000)
        defaults.set(succeededAt, forKey: AppSyncControl.lastSucceededAtKey)

        let (control, events) = makeControl(in: name)
        events.yield(
            SyncEvent(
                activity: .upload,
                startDate: succeededAt.addingTimeInterval(60),
                endDate: succeededAt.addingTimeInterval(61),
                succeeded: false))

        let failed = try #require(await awaitStatus(on: control) { $0.phase == .failed })
        // THE EXACT PAIR THAT WAS WRONG ON 2026-09-11: `.failed` draws "Could not sync", and a nil
        // timestamp draws "Not synced yet" beneath it — which is what a device with no account says.
        #expect(failed.lastSucceededAt == succeededAt)
    }

    @Test("A launch that is not mirroring reports off, and keeps listening to nothing")
    func aStoppedLaunchReportsOff() async throws {
        let (name, defaults) = try scratchDomain()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Date(timeIntervalSince1970: 1_757_002_000), forKey: AppSyncControl.lastSucceededAtKey)

        let (control, events) = makeControl(in: name, isRunning: false)
        events.yield(
            SyncEvent(
                activity: .download,
                startDate: Date(timeIntervalSince1970: 1_757_003_000),
                endDate: Date(timeIntervalSince1970: 1_757_003_001),
                succeeded: true))

        #expect(await control.status.phase == .off)
        // The stream ends rather than being held open for the life of a screen that will hear
        // nothing — so this loop terminates, and a regression here hangs the suite rather than
        // failing it quietly.
        var count = 0
        for await _ in control.statusUpdates() { count += 1 }
        #expect(count == 1)
    }
}
