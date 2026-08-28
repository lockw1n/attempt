import Foundation
import PowerliftingCore
import RepositoryInterface

/// `FR-1.8.2`'s de-duplication: which of a source's samples become rows, and under whose identity.
///
/// **The window is a calendar day, and that is forced rather than chosen.** `FR-1.8.1`'s form
/// offers a date and no time, so a reading a person typed is stored at the start of its day and
/// carries no instant to compare against; a `± n minutes` rule would measure a real 07:14 sample
/// against a synthetic midnight, never match, and duplicate every day that was also typed. The day
/// is the only granularity the two sources share, and it is already the unit ``BodyweightAverage``
/// measures its window in.
///
/// **A day a person entered themselves wins, and is never overwritten** — the direction the schema
/// default was chosen for. A day carrying a soft-deleted row is treated the same way, so an import
/// cannot resurrect a reading that was deleted.
///
/// **One imported row per day, replaced in place.** A scale that syncs three times before breakfast
/// would otherwise weigh that morning three times in the seven-day average; the day's latest sample
/// is the one a lifter means, and it is written under the id of the row the last import left, so a
/// second run moves the value rather than adding a row beside it.
enum HealthBodyweightImport {
    /// What an import would do, worked out before any of it is written.
    struct Plan: Equatable {
        /// The rows to save, oldest first — some new, some replacing what a previous import wrote.
        let entries: [BodyweightEntry]

        /// How many of the sample's days were left alone because the log already had that day.
        let daysAlreadyEntered: Int
    }

    /// Works out the import without performing it.
    ///
    /// - Parameters:
    ///   - samples: What the source disclosed, in any order.
    ///   - existing: The whole log, **soft-deleted rows included** — a tombstone is what stops a
    ///     deleted reading coming back on the next import.
    ///   - calendar: Whose days the matching window is measured in (`G-3.4`).
    ///   - now: The stamp every written row takes.
    /// - Returns: The rows to save and the count of days that already had a reading.
    static func plan(
        samples: some Sequence<BodyweightSample>,
        existing: some Sequence<BodyweightEntry>,
        calendar: Calendar,
        now: Date
    ) -> Plan {
        var owned: Set<Date> = []
        var replaceable: [Date: BodyweightEntry] = [:]
        var takenIDs: Set<UUID> = []
        for entry in existing {
            let day = calendar.startOfDay(for: entry.date)
            takenIDs.insert(entry.id)
            // `.manual` rather than `!= .healthKit` on purpose: an unreadable source resolves to
            // `.manual`, and this module's rule is that a row it cannot vouch for is the user's.
            if entry.source == .manual || entry.deletedAt != nil {
                owned.insert(day)
            } else if let held = replaceable[day], held.id.uuidString <= entry.id.uuidString {
                continue  // A second live imported row on one day: replace one, leave the rest.
            } else {
                replaceable[day] = entry
            }
        }

        var latest: [Date: BodyweightSample] = [:]
        var alreadyEntered: Set<Date> = []
        for sample in samples {
            let day = calendar.startOfDay(for: sample.date)
            guard !owned.contains(day) else {
                alreadyEntered.insert(day)
                continue
            }
            let held = latest[day]
            let isLater =
                held.map { ($0.date, $0.id.uuidString) < (sample.date, sample.id.uuidString) }
                ?? true
            if isLater { latest[day] = sample }
        }

        var entries: [BodyweightEntry] = []
        for (day, sample) in latest {
            if let row = replaceable[day] {
                // Nothing to write where the day's reading has not moved: an unconditional save
                // would restamp `updatedAt`, which is `G-2.4`'s conflict key.
                guard row.date != sample.date || row.weight != sample.weight else { continue }
                entries.append(entry(sample, id: row.id, createdAt: row.createdAt, now: now))
            } else if !takenIDs.contains(sample.id) {
                entries.append(entry(sample, id: sample.id, createdAt: now, now: now))
            }
            // A sample whose id already belongs to some other row is dropped rather than written:
            // saving it would replace a row this import does not own.
        }
        return Plan(
            entries: entries.sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) },
            daysAlreadyEntered: alreadyEntered.count)
    }

    /// The imported rows a typed reading supersedes — `FR-1.8.2`'s day rule, the other way round.
    ///
    /// ``plan(samples:existing:calendar:now:)`` refuses a day the log already holds, which settles
    /// the ordering where the reading was typed first. This settles the other one. A day imported
    /// *before* the lifter typed it would otherwise carry both rows, and `FR-1.8.3`'s window
    /// averages readings rather than days — so that day would weigh twice and the average would
    /// report a number neither reading says. A later import does not repair it either: by then the
    /// day is one the log owns, and the stale row is left alone forever.
    ///
    /// **The imported row is retired rather than edited.** A tombstone is also what stops the next
    /// import writing it straight back.
    ///
    /// - Parameters:
    ///   - entry: The reading just written. Anything but a live manual row supersedes nothing.
    ///   - existing: The live rows. Tombstones are already retired and need no second one.
    ///   - calendar: Whose days the window is measured in (`G-3.4`).
    /// - Returns: The rows to soft-delete, in a stable order.
    static func supersededImports(
        by entry: BodyweightEntry,
        in existing: some Sequence<BodyweightEntry>,
        calendar: Calendar
    ) -> [UUID] {
        guard entry.source == .manual, entry.deletedAt == nil else { return [] }
        let day = calendar.startOfDay(for: entry.date)
        // `.healthKit` rather than `!= .manual`, `plan`'s rule read the other way: this retires
        // only a row this module can vouch for having written itself.
        return
            existing
            .filter {
                $0.id != entry.id && $0.deletedAt == nil && $0.source == .healthKit
                    && calendar.startOfDay(for: $0.date) == day
            }
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
    }

    /// One sample as the row it becomes.
    ///
    /// **The sample's own instant, not the start of its day.** It is when the scale read, the day
    /// grouping is derived from it either way, and flattening it would throw away the only thing
    /// that tells two readings on one morning apart.
    private static func entry(
        _ sample: BodyweightSample, id: UUID, createdAt: Date, now: Date
    ) -> BodyweightEntry {
        BodyweightEntry(
            id: id,
            createdAt: createdAt,
            updatedAt: now,
            deletedAt: nil,
            date: sample.date,
            weight: sample.weight,
            source: .healthKit)
    }
}
