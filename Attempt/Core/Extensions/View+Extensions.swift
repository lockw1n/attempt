//
//  View+Extensions.swift
//  Attempt
//
//  Created by lockw1n on 01.08.2026.
//

import SwiftUI

extension View {
    /// Standard card treatment: padded, rounded, on the grouped-content background.
    func cardStyle() -> some View {
        padding(Theme.Spacing.medium)
            .background(.background.secondary, in: .rect(cornerRadius: Theme.Radius.medium))
    }

    /// Constrains content to a readable width and centres it — a no-op on
    /// compact iPhone widths, meaningful on iPad and landscape.
    func readableWidth() -> some View {
        frame(maxWidth: Theme.Layout.maxContentWidth)
            .frame(maxWidth: .infinity)
    }

    /// Runs `action` the first time the view appears, and not on subsequent
    /// appearances (unlike `onAppear`, which fires on every navigation return).
    func onFirstAppear(_ action: @escaping () async -> Void) -> some View {
        modifier(FirstAppearModifier(action: action))
    }
}

private struct FirstAppearModifier: ViewModifier {
    let action: () async -> Void
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content.task {
            guard !hasAppeared else { return }
            hasAppeared = true
            await action()
        }
    }
}
