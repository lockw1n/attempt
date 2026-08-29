import Foundation
import Testing

@testable import RepositoryInterface

// FR-1.12.2. The reducer is the whole of the sync screen's logic, and it is here rather than in
// `Persistence` because the vocabulary is: a feature module names this module and never that one.
//
// THE SUBJECT IS `endDate`, NOT `succeeded`. CloudKit reports `succeeded == false` for the entire
// duration of an attempt that is going perfectly well — the flag only means anything once the
// attempt is over. A reducer that read it directly would put the screen into a failure state on
// every single sync, and recover only when the sync finished. Half these cases exist to pin that.

private let start = Date(timeIntervalSince1970: 1_000)
private let finish = Date(timeIntervalSince1970: 1_060)
private let earlier = Date(timeIntervalSince1970: 500)

@Suite("Sync status")
struct SyncStatusTests {
    @Test("An attempt still running is active, not failed — `succeeded` is false throughout one")
    func runningAttemptIsActive() {
        let event = SyncEvent(activity: .upload, startDate: start, endDate: nil, succeeded: false)
        let status = SyncStatus.waiting.applying(event)

        #expect(status.phase == .active(.upload))
        // Anchored to nil rather than to another optional: nothing has succeeded yet, and a
        // comparison of two optionals would be satisfied by both being empty.
        #expect(status.lastSucceededAt == nil)
    }

    @Test("A running attempt does not disturb the last good time")
    func runningAttemptKeepsLastSuccess() {
        let status = SyncStatus(phase: .idle, lastSucceededAt: earlier)
            .applying(SyncEvent(activity: .download, startDate: start))

        #expect(status.phase == .active(.download))
        #expect(status.lastSucceededAt == Date(timeIntervalSince1970: 500))
    }

    @Test("A finished, successful attempt is idle and moves the timestamp to its end")
    func successMovesTimestamp() {
        let event = SyncEvent(
            activity: .download, startDate: start, endDate: finish, succeeded: true)
        let status = SyncStatus.waiting.applying(event)

        #expect(status.phase == .idle)
        #expect(status.lastSucceededAt == Date(timeIntervalSince1970: 1_060))
    }

    @Test("A failure keeps the last good time — that is the useful half of a failure")
    func failureKeepsLastSuccess() {
        let event = SyncEvent(
            activity: .upload, startDate: start, endDate: finish, succeeded: false)
        let status = SyncStatus(phase: .idle, lastSucceededAt: earlier).applying(event)

        #expect(status.phase == .failed)
        #expect(status.lastSucceededAt == Date(timeIntervalSince1970: 500))
    }

    @Test("A failure with nothing behind it reports no last good time rather than its own end")
    func failureWithNoHistoryHasNoTimestamp() {
        let event = SyncEvent(
            activity: .upload, startDate: start, endDate: finish, succeeded: false)

        #expect(SyncStatus.waiting.applying(event).lastSucceededAt == nil)
    }

    @Test("An out-of-order success never walks the timestamp backwards")
    func timestampNeverGoesBackwards() {
        let late = SyncStatus(phase: .idle, lastSucceededAt: finish)
        let stale = SyncEvent(
            activity: .download, startDate: earlier, endDate: earlier, succeeded: true)

        #expect(late.applying(stale).lastSucceededAt == Date(timeIntervalSince1970: 1_060))
    }

    @Test("An event arriving after the lifter switched sync off is dropped (FR-1.12.3)")
    func offDropsEverything() {
        // Turning mirroring off does not cancel an attempt already in flight, so its completion
        // lands afterwards. Applying it would put the screen back into a phase the lifter just
        // left — and, worse, would draw "syncing" on a screen whose toggle reads off.
        let inFlight = SyncEvent(activity: .upload, startDate: start)
        let finished = SyncEvent(
            activity: .upload, startDate: start, endDate: finish, succeeded: true)

        #expect(SyncStatus.off.applying(inFlight) == SyncStatus.off)
        #expect(SyncStatus.off.applying(finished) == SyncStatus.off)
        #expect(SyncStatus.off.applying(finished).lastSucceededAt == nil)
    }

    @Test("Every activity survives the reduction", arguments: SyncActivity.allCases)
    func everyActivityIsReported(activity: SyncActivity) {
        let status = SyncStatus.waiting.applying(SyncEvent(activity: activity, startDate: start))

        #expect(status.phase == .active(activity))
    }

    @Test("The two named starting points are what they claim")
    func namedStatusesAreDistinct() {
        #expect(SyncStatus.waiting.phase == .idle)
        #expect(SyncStatus.off.phase == .off)
        #expect(SyncStatus.waiting.lastSucceededAt == nil)
        #expect(SyncStatus.waiting != SyncStatus.off)
    }
}
