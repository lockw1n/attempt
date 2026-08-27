import Foundation

/// How far back an estimated one-rep maximum looks (`FR-1.7.1`).
///
/// **A window on the *session* date, not on when the row was written.** A set corrected today
/// belongs to the workout it was performed in, so a history edit must not drag a six-month-old
/// session back into the window — which is what a filter on `createdAt` would do.
///
/// **Whole days, and the lower bound is inclusive.** A session falling exactly on the boundary is
/// inside; a lookback that excluded its own edge would have no date it was named for. Days rather
/// than seconds because the requirement is written in days and because a calendar day is not
/// 86,400 seconds twice a year.
///
/// **No upper bound.** A lookback is a floor on age, so a session dated ahead of the device clock —
/// skew, a timezone move — stays in rather than vanishing from a screen the user just logged it on.
public struct E1RMLookback: Sendable, Hashable {
    /// `FR-1.7.1`'s default: ninety days.
    public static let `default` = E1RMLookback(days: 90)

    /// How many days back the window reaches. Values below one are clamped to one — a zero-day
    /// window is one that answers nothing, which is not a configuration anybody means.
    public let days: Int

    /// Creates a window `days` long.
    public init(days: Int) {
        self.days = max(1, days)
    }

    /// The oldest session date this window admits, counting back from `now`.
    ///
    /// - Parameters:
    ///   - now: The instant the window is measured from.
    ///   - calendar: Which calendar's days to count. The user's, in the app.
    /// - Returns: The inclusive lower bound.
    public func earliest(from now: Date, in calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now)
            ?? now.addingTimeInterval(-Double(days) * 86_400)
    }

    /// The range of session dates this window admits — see the type's note on the missing ceiling.
    ///
    /// - Parameters:
    ///   - now: The instant the window is measured from.
    ///   - calendar: Which calendar's days to count.
    /// - Returns: The range to read sessions over.
    public func range(from now: Date, in calendar: Calendar = .autoupdatingCurrent) -> ClosedRange<Date> {
        earliest(from: now, in: calendar)...Date.distantFuture
    }
}
