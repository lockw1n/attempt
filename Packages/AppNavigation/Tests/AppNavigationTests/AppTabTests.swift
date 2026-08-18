import Testing

@testable import AppNavigation

/// `D-8` is resolved for the whole phase (Q-1.2), so the tab set is a fact a test can pin rather
/// than a shape that grows. The raw values are persisted, which makes them an interface too.
@Suite("Tabs")
struct AppTabTests {
    /// Q-1.2's resolution, in the order the tab bar draws: no fifth tab, no "More".
    @Test("there are exactly four tabs, in Home / Train / History / Settings order")
    func fourTabsInOrder() {
        #expect(AppTab.allCases == [.home, .train, .history, .settings])
    }

    /// Renaming a case would silently discard every stored stack keyed by the old spelling, so the
    /// spellings are pinned here and a rename has to come past this test.
    @Test("the persisted spellings are pinned")
    func rawValues() {
        #expect(AppTab.home.rawValue == "home")
        #expect(AppTab.train.rawValue == "train")
        #expect(AppTab.history.rawValue == "history")
        #expect(AppTab.settings.rawValue == "settings")
    }

    /// A tab bar with two identical icons is a tab bar with one usable icon.
    @Test("each tab has its own symbol")
    func symbolsAreDistinct() {
        let symbols = AppTab.allCases.map(\.symbolName)
        #expect(Set(symbols).count == 4)
        #expect(!symbols.contains(""))
    }
}
