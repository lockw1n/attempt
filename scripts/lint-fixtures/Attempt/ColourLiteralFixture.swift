// FIXTURE — must trigger `no_color_literals` (G-7.7).
//
// Not compiled by any target and not linted by a normal run: `scripts/` is outside every package
// and outside `.swiftlint.yml`'s `included`. scripts/verify-lint-rules.sh lints it explicitly and
// fails if the rule below stops firing.
//
// The directory name `Attempt/` is load-bearing — the rule is scoped by a path regex, so a
// fixture stored anywhere else would silently not match and would prove nothing.

import SwiftUI

struct ColourLiteralFixture: View {
    var body: some View {
        Text("hard-coded colour")
            .foregroundStyle(Color(red: 0.2, green: 0.4, blue: 0.6))
    }
}
