import Foundation
import Testing

@testable import AppNavigation

/// The store is the process-restart half: everything here is "write it, throw the object away, read
/// it back". A test suite gets its own defaults suite, so two of these running at once cannot see
/// each other's key.
@Suite("Navigation state store")
struct NavigationStateStoreTests {
    private static func makeDefaults() throws -> UserDefaults {
        let name = "AppNavigationTests.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: name))
    }

    /// A first launch has nothing stored, and that has to be distinguishable from a stored default —
    /// `nil` is what makes the app open at Home rather than at whatever an empty decode produced.
    @Test("an empty store loads nothing")
    func emptyStoreLoadsNil() throws {
        let store = UserDefaultsNavigationStateStore(defaults: try Self.makeDefaults())
        #expect(store.load() == nil)
    }

    /// The whole restoration path, end to end.
    @Test("a saved snapshot loads back with its tab and depth")
    func saveThenLoad() throws {
        let defaults = try Self.makeDefaults()
        let store = UserDefaultsNavigationStateStore(defaults: defaults)
        let id = UUID()
        let route = Route.exerciseLibrary(.exerciseDetail(exerciseID: id))
        store.save(NavigationSnapshot(selectedTab: .train, stacks: [.train: [route]]))

        let loaded = try #require(UserDefaultsNavigationStateStore(defaults: defaults).load())
        #expect(loaded.selectedTab == .train)
        #expect(loaded.stacks[.train] == [route])
    }

    /// A save replaces; it does not merge. A restored app showing a stack the user left two launches
    /// ago would be worse than one showing none.
    @Test("saving again replaces what was stored")
    func saveReplaces() throws {
        let defaults = try Self.makeDefaults()
        let store = UserDefaultsNavigationStateStore(defaults: defaults)
        store.save(NavigationSnapshot(selectedTab: .train, stacks: [.train: [.training(.activeSession)]]))
        store.save(NavigationSnapshot(selectedTab: .settings))

        let loaded = try #require(store.load())
        #expect(loaded.selectedTab == .settings)
        #expect(loaded.stacks.isEmpty)
    }

    /// Bytes this version cannot read are indistinguishable from none — the degrade rule, at the
    /// layer where a throw would otherwise reach `AttemptApp.init` and take the launch with it.
    ///
    /// The store is proven to be reading the key *before* the bytes are corrupted. Writing to a key
    /// literal instead would pass on a store that reads some other key entirely, since "no such
    /// key" and "unreadable" are both `nil` — which is exactly what this test cannot afford to
    /// confuse.
    @Test("unreadable stored bytes load as no stored state")
    func corruptDataLoadsNil() throws {
        let defaults = try Self.makeDefaults()
        let key = "navigation.snapshot.corrupt"
        let store = UserDefaultsNavigationStateStore(defaults: defaults, key: key)
        store.save(NavigationSnapshot(selectedTab: .history))
        #expect(store.load()?.selectedTab == .history)

        defaults.set(Data("not a snapshot".utf8), forKey: key)
        #expect(store.load() == nil)
    }

    /// The default key is what `AttemptApp` stores under, so it is persisted interface in the same
    /// way `AppTab`'s raw values are: changing it drops every user's position at the next launch.
    @Test("the default key is pinned")
    func defaultKeyIsPinned() throws {
        let defaults = try Self.makeDefaults()
        UserDefaultsNavigationStateStore(defaults: defaults)
            .save(NavigationSnapshot(selectedTab: .history))

        #expect(defaults.data(forKey: "navigation.snapshot.v1") != nil)
    }

    /// The key is versioned so a future shape can be given its own; that only works if this one
    /// actually reads the key it was constructed with.
    @Test("the store reads and writes the key it was given")
    func keyIsHonoured() throws {
        let defaults = try Self.makeDefaults()
        let other = UserDefaultsNavigationStateStore(defaults: defaults, key: "other")
        other.save(NavigationSnapshot(selectedTab: .history))

        #expect(UserDefaultsNavigationStateStore(defaults: defaults).load() == nil)
        #expect(UserDefaultsNavigationStateStore(defaults: defaults, key: "other").load()?.selectedTab == .history)
    }
}
