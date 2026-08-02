// FIXTURE — must trigger `no_raw_font_sizes` (G-7.7). See ColourLiteralFixture.swift for why
// this lives here and why the `Attempt/` path segment matters.

import SwiftUI

struct FontSizeFixture: View {
    var body: some View {
        Text("raw point size")
            .font(.system(size: 17))
    }
}
