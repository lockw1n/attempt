import Foundation
import RemoteContent

/// Whether the running build is still allowed to run (`TR-0.5.4`).
///
/// **Blocking takes three things at once**: a resolved `flags.json`, a minimum version that parses,
/// and a running version that parses. Anything missing is ``allowedByDefault(_:)`` — a kill switch
/// that fired on unreadable configuration would brick every installed copy the first time the
/// endpoint had a bad afternoon.
///
/// The prompt itself is the view layer's. ``blocked(minimum:running:)`` carries the two numbers such
/// a prompt needs and no copy, the same split the published payloads draw between a field and its
/// consumer.
public enum UpgradeDecision: Equatable, Sendable {
    /// The published minimum was read and the running build meets it.
    case allowed(minimum: AppVersion, running: AppVersion)

    /// Nothing readable said otherwise, for this reason. Never a decision *to* allow — a decision
    /// that could not be made.
    case allowedByDefault(FailOpenReason)

    /// The running build is below the published minimum, which is the one case that blocks.
    case blocked(minimum: AppVersion, running: AppVersion)

    /// Whether the app must show a blocking upgrade prompt.
    public var isBlocking: Bool {
        if case .blocked = self { true } else { false }
    }
}

/// Why the kill switch could not be evaluated, and so did not fire.
public enum FailOpenReason: Equatable, Sendable, CustomStringConvertible {
    /// Neither the cache nor the app bundle produced a usable `flags.json` — offline on first
    /// launch, or a build whose bundled copy is broken.
    case noConfiguration

    /// A resolved payload that is not a `flags.json`. Carries the decoder's description.
    ///
    /// Unreachable through ``ContentFetcher/upgradeDecision(runningVersion:)``, which resolves only
    /// validated bytes — but the gate takes any payload, and a `try!` here would be the one crash
    /// this whole type exists to avoid.
    case undecodableConfiguration(String)

    /// A published minimum that is not a version. Carries what was published.
    ///
    /// Reachable: the payload validator refuses only a *blank* minimum, so any non-empty typo
    /// caches and resolves and arrives here.
    case unreadableMinimumVersion(String)

    /// The running build declares no version at all.
    case runningVersionUnavailable

    /// The running build declares a version that is not one. Carries what it declared.
    case unreadableRunningVersion(String)

    /// A line a reader can act on without opening this file.
    public var description: String {
        switch self {
        case .noConfiguration:
            "no readable flags.json was available"
        case .undecodableConfiguration(let detail):
            "the flags payload could not be decoded: \(detail)"
        case .unreadableMinimumVersion(let published):
            "the published minimum version '\(published)' is not a version"
        case .runningVersionUnavailable:
            "this build declares no version"
        case .unreadableRunningVersion(let declared):
            "this build's version '\(declared)' is not a version"
        }
    }
}

/// `TR-0.5.4`'s minimum-supported-version kill switch.
public enum UpgradeGate {
    /// Decides whether `runningVersion` may keep running, given whatever `flags.json`
    /// `ContentFetcher.resolve(_:)` answered with.
    ///
    /// The configuration is read before the running version, so a build with no version of its own
    /// still reports the configuration's fault first when both are broken — that is the one an
    /// author can fix.
    ///
    /// - Parameters:
    ///   - runningVersion: What this build declares, or `nil` when it declares nothing.
    ///   - configuration: A resolved `flags.json`, or `nil` when none resolved.
    public static func decide(
        runningVersion: String?,
        against configuration: ResolvedContent?
    ) -> UpgradeDecision {
        guard let configuration else { return .allowedByDefault(.noConfiguration) }

        let flags: RemoteFlags
        do {
            flags = try JSONDecoder().decode(RemoteFlags.self, from: configuration.data)
        } catch {
            return .allowedByDefault(.undecodableConfiguration(String(describing: error)))
        }

        guard let minimum = AppVersion(flags.minimumSupportedVersion) else {
            return .allowedByDefault(.unreadableMinimumVersion(flags.minimumSupportedVersion))
        }
        guard let runningVersion else { return .allowedByDefault(.runningVersionUnavailable) }
        guard let running = AppVersion(runningVersion) else {
            return .allowedByDefault(.unreadableRunningVersion(runningVersion))
        }

        return running < minimum
            ? .blocked(minimum: minimum, running: running)
            : .allowed(minimum: minimum, running: running)
    }
}

extension ContentFetcher {
    /// The kill switch's answer for this launch, from the `flags.json` already resolved.
    ///
    /// Synchronous and touching no transport, like every other `resolve(_:)` caller: a launch that
    /// had to await the network to learn whether it may run would fail closed whenever the network
    /// was slow, which is the failure mode `TR-0.5.4` is written against.
    ///
    /// - Parameter runningVersion: Defaults to what the main bundle declares.
    public func upgradeDecision(
        runningVersion: String? = RunningBuild.shortVersionString()
    ) -> UpgradeDecision {
        UpgradeGate.decide(runningVersion: runningVersion, against: resolve(.flags))
    }
}

/// What the running build says its version is.
public enum RunningBuild {
    /// The bundle's `CFBundleShortVersionString`, or `nil` when it declares none.
    public static func shortVersionString(in bundle: Bundle = .main) -> String? {
        shortVersionString(in: bundle.infoDictionary)
    }

    /// The same lookup over an info dictionary, which is the only shape a test can supply.
    static func shortVersionString(in info: [String: Any]?) -> String? {
        info?["CFBundleShortVersionString"] as? String
    }
}
