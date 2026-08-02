// FIXTURE — must trigger `no_magic_spacing` (G-7.7). See ColourLiteralFixture.swift for why
// this lives here and why the `Attempt/` path segment matters.

import SwiftUI

struct SpacingFixture: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("magic numbers")
                .padding(16)
        }
    }
}
