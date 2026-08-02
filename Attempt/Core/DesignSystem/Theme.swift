//
//  Theme.swift
//  Attempt
//
//  Created by lockw1n on 01.08.2026.
//

import SwiftUI

/// Design tokens. Reach for these instead of hard-coding numbers in views —
/// changing a value here restyles the whole app.
enum Theme {
    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
    }

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 20
    }

    enum Layout {
        /// Keeps text readable on iPad and landscape iPhone.
        static let maxContentWidth: CGFloat = 640
        static let minTapTarget: CGFloat = 44
    }

    enum Animation {
        static let standard: SwiftUI.Animation = .snappy(duration: 0.25)
        static let emphasized: SwiftUI.Animation = .snappy(duration: 0.4, extraBounce: 0.1)
    }
}
