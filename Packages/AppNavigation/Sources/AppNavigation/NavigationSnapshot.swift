/// Where the user is, in a form that survives a process restart (`TR-1.1`).
///
/// Two rules, both of which the decoder rather than the type enforces:
///
/// - **A stored state never prevents a launch.** Navigation position is not the user's data — it is
///   re-derivable in one tap and nothing upstream re-supplies it — so the four-way rule's second
///   question answers *degrade*, not *preserve*. An unreadable selected tab opens Home; an
///   unreadable ``Route`` costs that tab its whole stack and nothing else.
/// - **A stack is discarded whole, never trimmed.** Dropping the one route a version no longer
///   understands and keeping the rest produces a stack whose depth lies — a detail screen with no
///   list behind it — so the tab opens at its root instead.
///
/// An empty stack is the *absence* of a stack: ``init(selectedTab:stacks:)`` drops empty entries, so
/// two states a user cannot tell apart also encode identically.
public struct NavigationSnapshot: Hashable, Sendable, Codable {
    /// The tab in front.
    public let selectedTab: AppTab

    /// What each tab has pushed above its root. A tab sitting at its root has no entry.
    public let stacks: [AppTab: [Route]]

    /// A first launch: Home, nothing pushed.
    public static let initial = NavigationSnapshot()

    /// Creates a snapshot, dropping any empty stack.
    public init(selectedTab: AppTab = .home, stacks: [AppTab: [Route]] = [:]) {
        self.selectedTab = selectedTab
        self.stacks = stacks.filter { !$0.value.isEmpty }
    }

    private enum CodingKeys: String, CodingKey {
        case selectedTab
        case stacks
    }

    /// One tab's stack. An array of these rather than a dictionary keyed by tab, because a
    /// dictionary's encoding is not ordered and this one is: `AppTab.allCases` order, so the same
    /// state produces the same bytes twice running.
    private struct TabStack: Codable {
        let tab: AppTab
        let routes: [Route]
    }

    /// A `TabStack` that decodes to `nil` instead of throwing.
    ///
    /// The failure has to be swallowed *inside* an element rather than by a `try?` around
    /// `decode(TabStack.self)`: an unkeyed container does not advance its index past a throw, so the
    /// obvious spelling of "skip the bad one" loops forever.
    private struct LenientTabStack: Decodable {
        let stack: TabStack?

        init(from decoder: any Decoder) {
            stack = try? TabStack(from: decoder)
        }
    }

    /// Writes the position, stacks first in tab-bar order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedTab, forKey: .selectedTab)
        let ordered = AppTab.allCases.compactMap { tab in
            stacks[tab].map { TabStack(tab: tab, routes: $0) }
        }
        try container.encode(ordered, forKey: .stacks)
    }

    /// Decodes a stored snapshot, degrading rather than throwing on anything it cannot read.
    ///
    /// The keyed container itself is still allowed to throw: bytes that are not an object at all are
    /// not a navigation state to be salvaged, and ``NavigationStateStore`` treats that as "no stored
    /// state" the same way it treats an absent key.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tab = (try? container.decode(AppTab.self, forKey: .selectedTab)) ?? .home
        let stored = (try? container.decode([LenientTabStack].self, forKey: .stacks)) ?? []
        var decoded: [AppTab: [Route]] = [:]
        for entry in stored.compactMap(\.stack) where decoded[entry.tab] == nil {
            decoded[entry.tab] = entry.routes
        }
        self.init(selectedTab: tab, stacks: decoded)
    }
}
