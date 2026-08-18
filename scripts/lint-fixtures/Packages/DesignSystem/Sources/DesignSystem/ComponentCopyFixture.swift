// Deliberate G-3.4 violation, on the component layer's path rather than a feature's.
//
// It proves the SECOND `included` entry of no_literal_ui_strings, which — unlike G-7.7's path
// lists — is load-bearing rather than decorative: this rule names no `Attempt/` path, so its
// filters are the only thing deciding what it scans, and a component writing its own copy is
// exactly the case the DesignSystem entry exists for.
import SwiftUI

struct ComponentCopyFixture: View {
    var body: some View {
        Text("No data yet")
    }
}
