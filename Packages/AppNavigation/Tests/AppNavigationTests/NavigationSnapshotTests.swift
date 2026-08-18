import Foundation
import Testing

@testable import AppNavigation

/// The snapshot is the whole of `TR-1.1`'s "serializable for restoration", so what these hold is
/// the restore: same tab, same depth, same payloads — and, where a version boundary makes that
/// impossible, a degrade that still launches.
@Suite("Navigation snapshot")
struct NavigationSnapshotTests {
    static let exerciseID = RouteTests.exerciseID
    static let sessionID = RouteTests.sessionID

    static let populated = NavigationSnapshot(
        selectedTab: .train,
        stacks: [
            .train: [.exerciseLibrary(.exerciseDetail(exerciseID: exerciseID)), .training(.activeSession)],
            .history: [.history(.session(sessionID: sessionID))],
        ]
    )

    /// Every tab carrying a stack. The ordering test needs all four: with two entries a
    /// dictionary-ordered encode reproduced the tab-bar order anyway, in eight runs out of eight.
    static let allTabs = NavigationSnapshot(
        selectedTab: .home,
        stacks: [
            .home: [.dashboard(.recentPersonalRecords)],
            .train: [.training(.activeSession)],
            .history: [.history(.session(sessionID: sessionID))],
            .settings: [.settings(.about)],
        ]
    )

    private static func encodedObject(_ snapshot: NavigationSnapshot) throws -> [String: Any] {
        let data = try JSONEncoder().encode(snapshot)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func decode(_ object: [String: Any]) throws -> NavigationSnapshot {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(NavigationSnapshot.self, from: data)
    }

    /// The deep-link claim, minus the simulator: a state restored from bytes is the state that was
    /// written down — tab, per-tab depth and the payload at the top of the stack.
    @Test("a populated snapshot round-trips: tab, depth and payload")
    func roundTrip() throws {
        let decoded = try JSONDecoder().decode(
            NavigationSnapshot.self,
            from: JSONEncoder().encode(Self.populated)
        )

        #expect(decoded == Self.populated)
        #expect(decoded.selectedTab == .train)
        #expect(decoded.stacks[.train]?.count == 2)
        #expect(decoded.stacks[.history]?.count == 1)
        #expect(decoded.stacks[.home] == nil)
        #expect(decoded.stacks[.train]?.last == .training(.activeSession))
    }

    /// An empty stack is the absence of a stack. Two states the user cannot tell apart must not be
    /// two values that compare unequal, or a "did this change?" check on the snapshot saves forever.
    @Test("an empty stack is dropped rather than stored")
    func emptyStacksNormalize() {
        let withEmpty = NavigationSnapshot(selectedTab: .home, stacks: [.train: [], .history: []])
        #expect(withEmpty.stacks.isEmpty)
        #expect(withEmpty == NavigationSnapshot.initial)
        #expect(NavigationSnapshot.initial.selectedTab == .home)
    }

    /// Ordered by `AppTab.allCases`, so the same state produces the same array twice running. Read
    /// back through `JSONSerialization` because asserting on the encoder's *key* order would be
    /// asserting on a per-process hash seed.
    ///
    /// All four tabs, because the assertion is probabilistic: an encode that walked the dictionary
    /// instead has to draw the tab-bar permutation by chance to survive this, and a two-entry
    /// fixture let it do so every time. Four leaves one permutation in twenty-four.
    @Test("stacks are encoded in tab-bar order")
    func stacksEncodeInTabOrder() throws {
        let object = try Self.encodedObject(Self.allTabs)
        let stacks = try #require(object["stacks"] as? [[String: Any]])
        #expect(
            stacks.compactMap { $0["tab"] as? String } == ["home", "train", "history", "settings"]
        )
    }

    /// Degrade, first half: an unreadable selected tab opens Home rather than refusing to launch.
    @Test("an unknown selected tab degrades to Home")
    func unknownSelectedTabDegrades() throws {
        var object = try Self.encodedObject(Self.populated)
        object["selectedTab"] = "more"

        let decoded = try Self.decode(object)
        #expect(decoded.selectedTab == .home)
        #expect(decoded.stacks[.train]?.count == 2)
    }

    /// Degrade, second half — and the load-bearing one: a stack holding a route this version cannot
    /// read is discarded **whole**, and the other tabs are untouched. A trimmed stack would restore
    /// a detail screen with no list behind it.
    @Test("a stack with an unreadable route is dropped, and only that stack")
    func unreadableRouteDropsItsStack() throws {
        var object = try Self.encodedObject(Self.populated)
        var stacks = try #require(object["stacks"] as? [[String: Any]])
        stacks[0]["routes"] = [["crossTraining": ["_0": [String: Any]()]]]
        object["stacks"] = stacks

        let decoded = try Self.decode(object)
        #expect(decoded.stacks[.train] == nil)
        #expect(decoded.stacks[.history]?.count == 1)
        #expect(decoded.stacks[.history]?.first == .history(.session(sessionID: Self.sessionID)))
        #expect(decoded.selectedTab == .train)
    }

    /// An unreadable tab in a stack entry takes that entry with it, for the same reason: there is no
    /// tab to put the routes on.
    @Test("a stack under an unknown tab is dropped")
    func unknownTabDropsItsStack() throws {
        var object = try Self.encodedObject(Self.populated)
        var stacks = try #require(object["stacks"] as? [[String: Any]])
        stacks[0]["tab"] = "more"
        object["stacks"] = stacks

        let decoded = try Self.decode(object)
        #expect(decoded.stacks.count == 1)
        #expect(decoded.stacks[.history]?.count == 1)
    }

    /// Two entries naming one tab: the first is kept. Arbitrary between the two, but not arbitrary
    /// that it is decided — last-wins would let a trailing entry overwrite a stack that decoded.
    @Test("a tab named twice keeps the first stack")
    func duplicateTabKeepsTheFirst() throws {
        var object = try Self.encodedObject(Self.populated)
        var stacks = try #require(object["stacks"] as? [[String: Any]])
        stacks.append([
            "tab": "train",
            "routes": [["training": ["_0": ["activeSession": [String: Any]()]]]],
        ])
        object["stacks"] = stacks

        let decoded = try Self.decode(object)
        #expect(decoded.stacks[.train] == Self.populated.stacks[.train])
        #expect(decoded.stacks[.train]?.count == 2)
    }

    /// Bytes that are not an object at all are not a navigation state to salvage — the throw is what
    /// ``UserDefaultsNavigationStateStore`` turns into "no stored state".
    @Test("bytes that are not a snapshot throw rather than decoding to a default")
    func nonObjectThrows() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(NavigationSnapshot.self, from: Data(#"[1,2,3]"#.utf8))
        }
    }
}
