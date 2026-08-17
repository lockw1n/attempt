import Foundation
import RemoteContent
import Testing

@testable import RemoteFetch

@Suite("UpgradeGate")
struct UpgradeGateTests {
    // MARK: - The comparison itself

    @Test("A build below the published minimum is blocked")
    func belowMinimumBlocks() throws {
        let payload = try flagsPayload(revision: 1, minimumSupportedVersion: "2.0.0")
        let minimum = try #require(AppVersion("2.0.0"))
        let running = try #require(AppVersion("1.9.9"))
        let decision = UpgradeGate.decide(runningVersion: "1.9.9", against: resolved(payload))

        #expect(decision.isBlocking)
        #expect(decision == .blocked(minimum: minimum, running: running))
    }

    @Test("A build at the published minimum is not blocked")
    func atMinimumDoesNotBlock() throws {
        let payload = try flagsPayload(revision: 1, minimumSupportedVersion: "2.0.0")
        let version = try #require(AppVersion("2.0.0"))
        let decision = UpgradeGate.decide(runningVersion: "2.0.0", against: resolved(payload))

        #expect(!decision.isBlocking)
        #expect(decision == .allowed(minimum: version, running: version))
    }

    @Test("At the minimum written to a different width is still at the minimum")
    func atMinimumAcrossWidthsDoesNotBlock() throws {
        // The shipping case: `MARKETING_VERSION` is `1.0` and the published minimum is `1.0.0`.
        let payload = try flagsPayload(revision: 1, minimumSupportedVersion: "1.0.0")
        #expect(!UpgradeGate.decide(runningVersion: "1.0", against: resolved(payload)).isBlocking)
    }

    @Test("A build above the published minimum is not blocked")
    func aboveMinimumDoesNotBlock() throws {
        let payload = try flagsPayload(revision: 1, minimumSupportedVersion: "2.0.0")
        let minimum = try #require(AppVersion("2.0.0"))
        let running = try #require(AppVersion("2.10.0"))
        let decision = UpgradeGate.decide(runningVersion: "2.10.0", against: resolved(payload))

        #expect(!decision.isBlocking)
        #expect(decision == .allowed(minimum: minimum, running: running))
    }

    // MARK: - Every way the switch fails open

    @Test("No configuration at all does not block")
    func noConfigurationDoesNotBlock() {
        let decision = UpgradeGate.decide(runningVersion: "0.1", against: nil)

        #expect(!decision.isBlocking)
        #expect(decision == .allowedByDefault(.noConfiguration))
    }

    @Test("A payload that is not flags.json does not block")
    func undecodableConfigurationDoesNotBlock() throws {
        let decision = UpgradeGate.decide(runningVersion: "0.1", against: resolved(malformedPayload))

        #expect(!decision.isBlocking)
        guard case .allowedByDefault(.undecodableConfiguration(let detail)) = decision else {
            Issue.record("expected an undecodable payload, got \(decision)")
            return
        }
        #expect(!detail.isEmpty)
    }

    @Test("A published minimum that is not a version does not block")
    func unreadableMinimumDoesNotBlock() throws {
        let payload = try flagsPayload(revision: 1, minimumSupportedVersion: "banana")
        let decision = UpgradeGate.decide(runningVersion: "0.1", against: resolved(payload))

        #expect(!decision.isBlocking)
        #expect(decision == .allowedByDefault(.unreadableMinimumVersion("banana")))
    }

    @Test("The payload validator lets an unreadable minimum through, so the gate has to")
    func unreadableMinimumIsAServedPayload() throws {
        // Not a defensive branch: `RemoteFlagsValidator` refuses only a *blank* minimum, so a typo
        // validates at publish time, caches, resolves, and arrives at the gate.
        let payload = try flagsPayload(revision: 1, minimumSupportedVersion: "banana")
        #expect(RemoteFlagsValidator.validate(payload).isEmpty)
        #expect(RemoteResource.flags.inspect(payload) == .usable(revision: 1))
    }

    @Test("A build that declares no version does not block")
    func missingRunningVersionDoesNotBlock() throws {
        let payload = try flagsPayload(revision: 1, minimumSupportedVersion: "2.0.0")
        let decision = UpgradeGate.decide(runningVersion: nil, against: resolved(payload))

        #expect(!decision.isBlocking)
        #expect(decision == .allowedByDefault(.runningVersionUnavailable))
    }

    @Test("A build whose version is not a version does not block")
    func unreadableRunningVersionDoesNotBlock() throws {
        let payload = try flagsPayload(revision: 1, minimumSupportedVersion: "2.0.0")
        let decision = UpgradeGate.decide(runningVersion: "1.0.0-beta", against: resolved(payload))

        #expect(!decision.isBlocking)
        #expect(decision == .allowedByDefault(.unreadableRunningVersion("1.0.0-beta")))
    }

    @Test("A broken configuration is reported before a broken running version")
    func configurationFaultIsReportedFirst() throws {
        let payload = try flagsPayload(revision: 1, minimumSupportedVersion: "banana")
        let decision = UpgradeGate.decide(runningVersion: "not a version", against: resolved(payload))

        #expect(decision == .allowedByDefault(.unreadableMinimumVersion("banana")))
    }

    @Test("A broken configuration is reported before a missing running version too")
    func configurationFaultOutranksAMissingRunningVersion() throws {
        // Both orders fail open, so this pins the diagnostic rather than the outcome: the published
        // minimum is the half an author can fix, so it is the half reported.
        let payload = try flagsPayload(revision: 1, minimumSupportedVersion: "banana")
        let decision = UpgradeGate.decide(runningVersion: nil, against: resolved(payload))

        #expect(decision == .allowedByDefault(.unreadableMinimumVersion("banana")))
    }

    @Test("Every fail-open reason says which one it is")
    func failOpenReasonsAreDistinct() {
        let reasons: [FailOpenReason] = [
            .noConfiguration,
            .undecodableConfiguration("detail"),
            .unreadableMinimumVersion("banana"),
            .runningVersionUnavailable,
            .unreadableRunningVersion("nope"),
        ]
        #expect(Set(reasons.map(\.description)).count == reasons.count)
        #expect(reasons.allSatisfy { !$0.description.isEmpty })
    }

    // MARK: - Through the fetcher

    @Test("The fetcher decides from the flags it already resolved, without touching the network")
    func fetcherBlocksFromACachedMinimum() throws {
        let cache = TemporaryCache().cache
        // Above the bundled edition, so `resolve` prefers it over the compiled-in copy.
        let payload = try flagsPayload(
            revision: RemoteFlags.published.revision + 1, minimumSupportedVersion: "3.0")
        try cache.write(payload, for: .flags)
        let fetcher = ContentFetcher(transport: RoutingTransport(), cache: cache)

        #expect(fetcher.upgradeDecision(runningVersion: "2.9").isBlocking)
        #expect(!fetcher.upgradeDecision(runningVersion: "3.0").isBlocking)
        #expect(!fetcher.upgradeDecision(runningVersion: "3.1").isBlocking)
    }

    @Test("A build with no cache and no bundled flags is not blocked")
    func fetcherFailsOpenWithNothingResolved() {
        let fetcher = ContentFetcher(
            baseURL: PublishedContent.baseURL,
            transport: RoutingTransport(),
            cache: TemporaryCache().cache
        ) { _ in throw URLError(.fileDoesNotExist) }

        #expect(fetcher.upgradeDecision(runningVersion: "0.1") == .allowedByDefault(.noConfiguration))
    }

    @Test("The bundled flags alone do not lock out the version this build ships")
    func bundledFlagsDoNotLockOutTheShippedBuild() throws {
        let fetcher = ContentFetcher(transport: RoutingTransport(), cache: TemporaryCache().cache)
        let minimum = try #require(AppVersion(RemoteFlags.published.minimumSupportedVersion))
        let running = try #require(AppVersion(shippedMarketingVersion))
        let decision = fetcher.upgradeDecision(runningVersion: shippedMarketingVersion)

        #expect(!decision.isBlocking)
        #expect(decision == .allowed(minimum: minimum, running: running))
    }

    // MARK: - Where the running version comes from

    @Test("The running version is the bundle's short version string")
    func readsShortVersionString() {
        #expect(RunningBuild.shortVersionString(in: ["CFBundleShortVersionString": "4.5"]) == "4.5")
    }

    @Test("A bundle that declares no usable short version string declares none")
    func missingShortVersionStringIsNil() {
        #expect(RunningBuild.shortVersionString(in: nil) == nil)
        #expect(RunningBuild.shortVersionString(in: [:]) == nil)
        #expect(RunningBuild.shortVersionString(in: ["CFBundleVersion": "12"]) == nil)
        // Present but not a string, which `as? String` has to refuse rather than describe.
        #expect(RunningBuild.shortVersionString(in: ["CFBundleShortVersionString": 3]) == nil)
    }
}

/// The version the app target ships (`MARKETING_VERSION`), written to the width the project writes
/// it — which is not the width `flags.json` publishes its minimum to.
private let shippedMarketingVersion = "1.0"
