import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface

/// Why a reading will not save (`FR-1.13.3`).
///
/// One reason at a time, in the order the form reads — the message sits under the save command and
/// names the next thing to fix.
enum BodyweightDraftRefusal: Equatable, CaseIterable {
    /// The field is empty, is not a number in this locale, or is negative.
    case notAWeight

    /// It is zero. Nobody weighs nothing, and a zero here would be averaged with real readings.
    case notPositive
}

/// What the bodyweight form holds while a reading is being entered (`FR-1.8.1`).
///
/// **Text rather than a number**, on `Logging.SetDraft`'s argument: a field bound to a `Double`
/// reverts what the user is halfway through typing, so the crossing happens once, on confirm, and
/// it is ``Localization/LocalizedNumberField``'s.
///
/// **The date is stored as the start of its day.** `BodyweightEntry.date` is the day the reading is
/// *for*, and two readings entered for the same day at different clock times must land in the same
/// window when the seven-day average is taken.
struct BodyweightEntryDraft: Equatable {
    /// The identity a new reading takes when this form is saved.
    ///
    /// Minted once with the draft rather than at each save, for `Logging.EquipmentProfileDraft`'s
    /// reason: the save is `async` and a second tap would otherwise insert a second row.
    let newEntryID: UUID

    /// The unit ``weightText`` is read in — the user's display preference (`G-3.1`).
    let unit: MassUnit

    /// The locale the field is parsed against (`G-3.4`).
    let locale: Locale

    /// The reading, as typed.
    var weightText: String = ""

    /// The day the reading is for. Today unless the user backdates it.
    var date: Date

    /// Which days a date belongs to (`G-3.4`).
    let calendar: Calendar

    /// An empty draft, dated `day`.
    ///
    /// - Parameters:
    ///   - unit: The unit the reading is entered in.
    ///   - locale: The locale the field is parsed against.
    ///   - calendar: Whose days the date is snapped to.
    ///   - day: What the date starts on. Defaults to now.
    ///   - newEntryID: The identity a saved reading takes. Pass the draft's own to re-seed a form
    ///     the user has already opened.
    init(
        unit: MassUnit,
        locale: Locale,
        calendar: Calendar = .current,
        day: Date = .now,
        newEntryID: UUID = UUID()
    ) {
        self.unit = unit
        self.locale = locale
        self.calendar = calendar
        self.date = day
        self.newEntryID = newEntryID
    }

    /// Whether nothing has been typed yet — the state a refusal must not be shown in.
    var isBlank: Bool {
        weightText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Why this draft will not save, or `nil` when it will.
    var refusal: BodyweightDraftRefusal? {
        guard let weight = LocalizedNumberField.weight(weightText, in: unit, locale: locale) else {
            return .notAWeight
        }
        return weight > .zero ? nil : .notPositive
    }

    /// Whether the command that writes this draft is available.
    var isSavable: Bool { refusal == nil }

    /// The record this draft describes, or `nil` when it is refused.
    ///
    /// **Always a new reading.** `FR-1.8.1` is entry with a date and nothing asks to correct one,
    /// so there is no row to carry an identity or a `createdAt` over from; the day a reading is
    /// *for* is ``date``, and backdating moves that rather than the stamps.
    ///
    /// - Returns: The record to save.
    func entry() -> BodyweightEntry? {
        guard let weight = LocalizedNumberField.weight(weightText, in: unit, locale: locale),
            weight > .zero
        else {
            return nil
        }
        let now = Date.now
        return BodyweightEntry(
            id: newEntryID,
            createdAt: now,
            updatedAt: now,
            // Rule 7: a soft-deleted row is not reinstated by a write from a form (`G-1.3`).
            deletedAt: nil,
            date: calendar.startOfDay(for: date),
            weight: weight,
            // `FR-1.8.2`'s HealthKit readings are T-1.51's; everything this form writes is the
            // user's own hand.
            source: .manual
        )
    }
}
