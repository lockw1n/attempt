import Foundation
import PowerliftingCore
import RepositoryInterface

/// One row of the bodyweight history: what was weighed, and the trend at that point (`FR-1.8.3`).
struct BodyweightReading: Identifiable, Equatable {
    /// The entry this row draws.
    let id: UUID

    /// The day the reading is for — not when it was entered (`FR-1.8.1`).
    let date: Date

    /// What was weighed.
    let weight: Weight

    /// The seven-day average ending on ``date``, or `nil` where that window holds too few readings
    /// to average. See ``BodyweightAverage``.
    let average: Weight?
}

/// `FR-1.8.3`'s seven-day rolling average, over the readings there actually are.
///
/// **The window is days, the average is over readings, and the two are deliberately not the same
/// number.** A lifter does not weigh in every morning, so requiring seven readings would leave the
/// average blank for almost everyone; averaging whatever falls in the seven calendar days ending on
/// a reading's own day is the figure a lifter means by "my weekly average". Two readings on one day
/// both count — they are readings, not days.
///
/// **Below ``minimumReadings`` it refuses rather than answers.** A single reading averaged with
/// itself is that reading, presented as a trend it cannot be evidence of; `FR-1.13.3` says to name
/// what would be enough instead, and the screen's copy does.
///
/// **Feature-local until a second consumer appears.** Nothing else in the app averages a bodyweight;
/// `T-1.51`'s HealthKit readings land in the same log and are read through this same screen.
enum BodyweightAverage {
    /// How many calendar days the window spans, its last day included.
    static let windowDays = 7

    /// How many readings the window needs before an average is drawn at all.
    static let minimumReadings = 2

    /// Every entry as a row, newest first, each carrying its own window's average.
    ///
    /// **One walk over a sorted log, not a window scan per row.** Both of a window's bounds move
    /// forward with the reading it ends on, so the first and last entries inside it never step
    /// backwards and one pair of indices can cross the whole log once. Re-filtering every reading
    /// for every row is the same answer at `n²` comparisons, and this list is unbounded.
    ///
    /// - Parameters:
    ///   - entries: The log, in any order. Soft-deleted rows must already be excluded.
    ///   - calendar: Whose days the window is measured in (`G-3.4`).
    /// - Returns: The rows, newest first, ties broken on the identifier so the order is stable.
    static func readings(
        from entries: some Sequence<BodyweightEntry>, calendar: Calendar
    ) -> [BodyweightReading] {
        let ascending = entries.sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
        var first = 0
        var past = 0
        var rows: [BodyweightReading] = []
        rows.reserveCapacity(ascending.count)
        for entry in ascending {
            var average: Weight?
            if let window = window(endingOn: entry.date, calendar: calendar) {
                while first < ascending.count, ascending[first].date < window.lowerBound {
                    first += 1
                }
                while past < ascending.count, ascending[past].date < window.upperBound {
                    past += 1
                }
                let inWindow = ascending[first..<past]
                if inWindow.count >= minimumReadings {
                    average = mean(of: inWindow.map(\.weight))
                }
            }
            rows.append(
                BodyweightReading(
                    id: entry.id, date: entry.date, weight: entry.weight, average: average))
        }
        return Array(rows.reversed())
    }

    /// The average of the readings in the seven days ending on `day`.
    ///
    /// - Parameters:
    ///   - day: The window's last day; the window opens six days before it.
    ///   - entries: The log, in any order.
    ///   - calendar: Whose days the window is measured in.
    /// - Returns: The mean, or `nil` when the window holds fewer than ``minimumReadings``.
    static func rolling(
        endingOn day: Date, over entries: some Sequence<BodyweightEntry>, calendar: Calendar
    ) -> Weight? {
        guard let window = window(endingOn: day, calendar: calendar) else { return nil }
        let inWindow = entries.filter { window.contains($0.date) }
        guard inWindow.count >= minimumReadings else { return nil }
        return mean(of: inWindow.map(\.weight))
    }

    /// The seven calendar days ending on `day`, from the first day's start to the last day's end.
    ///
    /// A half-open range, so a reading stamped at any time on the closing day is inside it and one
    /// stamped at midnight on the day after is not.
    private static func window(endingOn day: Date, calendar: Calendar) -> Range<Date>? {
        let lastDay = calendar.startOfDay(for: day)
        guard
            let start = calendar.date(byAdding: .day, value: -(windowDays - 1), to: lastDay),
            let end = calendar.date(byAdding: .day, value: 1, to: lastDay)
        else {
            return nil
        }
        return start..<end
    }

    /// The mean of `weights`, rounded to the nearest gram, halves away from zero.
    ///
    /// **A sum that will not fit refuses instead of dropping a term**, which is where this parts
    /// company with `DerivedValues.Tonnage`: a total missing one load is smaller than it should be,
    /// while a *mean* missing one reading is a plausible number that is simply wrong. Unreachable
    /// from readings a person could stand on; reachable from a store this app did not write.
    private static func mean(of weights: [Weight]) -> Weight? {
        var sum = 0
        for weight in weights {
            let (running, overflowed) = sum.addingReportingOverflow(weight.grams)
            guard !overflowed else { return nil }
            sum = running
        }
        let count = weights.count
        guard count > 0 else { return nil }
        let quotient = sum / count
        let remainder = sum % count
        guard abs(remainder) * 2 >= count else { return Weight(grams: quotient) }
        return Weight(grams: quotient + (sum < 0 ? -1 : 1))
    }
}
