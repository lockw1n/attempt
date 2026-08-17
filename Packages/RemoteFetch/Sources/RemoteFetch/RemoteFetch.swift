// RemoteFetch — the published payloads on their way into the app (TR-0.5.3, G-2.1, G-2.3, NFR-1.7).
//
// It sits above `RemoteContent` and `SeedContent` because it is the one place that names both; this
// package's manifest has the argument. What it produces is bytes, and it hands them on — nothing
// here knows what a stored row looks like.
//
// Module-wide rules, stated once here:
//
//   - NOTHING BLOCKS ON THE NETWORK. `ContentFetcher.resolve(_:)` is synchronous and holds no
//     transport, so a launch path *cannot* await a fetch through it; `refresh(_:)` is the async half
//     and is scheduled beside a launch, never inside it. `G-2.3` is a property of the signatures
//     here rather than a convention a caller has to keep.
//
//   - A FETCH THAT FAILS IS NOT AN ERROR. `refresh(_:)` does not throw. Offline, timed out, refused
//     and unwritable all resolve to a `RefreshOutcome` the caller may ignore entirely, because the
//     fallback chain has already answered the only question the app actually asks.
//
//   - VALIDATE BEFORE CACHING, WITH THE PAYLOAD'S OWN VALIDATOR. The three validators here are the
//     ones the deploy tooling runs before publishing, so a body this build refuses is a body that
//     should never have been served. Validation before the write is what makes a malformed response
//     cost nothing: the previous copy stays.
//
//   - THE HIGHER `revision` WINS, WHICHEVER LEG IT IS ON. A cache is not preferred to the bundle on
//     rank — an app update ships a newer bundled catalogue than a cache filled before it. `revision`
//     answers "is this newer"; `schemaVersion` answers "can this be read at all" and is refused when
//     unrecognised, which is the trigger that sends a reader back down the chain.
