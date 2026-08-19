// The app target's side of no_literal_ui_strings: these literals are CORRECT and the rule must not
// fire on them. `LocalizedStringKey` resolves against `Bundle.main`, which is the app target's own
// catalogue, so a key written here reaches copy; the same literal in a package resolves against a
// bundle that has no such key. That asymmetry is why the rule names package paths only, and this
// file is the guard on it — if a later edit adds an `Attempt/.*` entry, the matching is unanchored
// against the absolute path and every literal in the repository becomes a violation.
import SwiftUI

struct AppCopyFixture: View {
    var body: some View {
        Text("app.tab.home")
            .navigationTitle("app.tab.settings")
    }
}
