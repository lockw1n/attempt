import SwiftUI

/// Which corner of a workout screen's toolbar an item sits in (`FR-18.4.1`, `FR-18.4.2`).
///
/// **Two named sides rather than a `ToolbarItemPlacement` at each call site**, because the
/// placement that means "leading" is iOS-only and this module also compiles for macOS — a host
/// passing `.topBarLeading` would be writing a `#if` into a view. The mapping is here; the hosts
/// name a side.
enum SessionToolbarSide {
    /// Beside Back. On iOS a leading item supplements the back button rather than replacing it.
    case leading

    /// The corner opposite Back, where Done is.
    case trailing

    /// Where SwiftUI puts it on this platform.
    ///
    /// **`.primaryAction` rather than `.topBarTrailing` for the trailing side**, because that is
    /// the placement the free workout's `⋯` already had and `OUT-18.6` keeps its toolbar exactly —
    /// the two spellings agree on iOS, and only the one that was there is evidence of that.
    var placement: ToolbarItemPlacement {
        switch self {
        case .leading:
            #if os(iOS)
                .topBarLeading
            #else
                .navigation
            #endif
        case .trailing:
            .primaryAction
        }
    }
}
