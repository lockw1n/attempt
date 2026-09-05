import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface

/// Why a training max will not save (`FR-1.13.3`).
///
/// One reason at a time, in the order the form reads — the message sits under the save command and
/// names the next thing to fix. `BodyweightEntryDraft`'s shape, and it stops one short of that
/// type's: a training max of zero is refused for the reason a bodyweight of zero is, but a
/// *negative* one is refused here too, since a load read against it would come out backwards.
enum TrainingMaxDraftRefusal: Equatable, CaseIterable {
    /// The field is empty, is not a number in this locale, or is negative —
    /// ``Localization/LocalizedNumberField`` refuses a signed value, so an assisted-work figure
    /// lands here rather than in ``notPositive``.
    case notAWeight

    /// It is zero. Nothing is prescribed as a percentage of nothing — see
    /// ``PowerliftingCore/Weight/percentOfTrainingMax(_:)``, which refuses the same value.
    ///
    /// The guard below is written `> 0` rather than `!= 0` all the same: `Weight` is signed on
    /// purpose, and a parser that started accepting a sign would otherwise pass one through here.
    case notPositive
}

/// What the change sheet holds while a training max is being entered (`FR-16.7.2`).
///
/// **Text rather than a number**, on `Settings.BodyweightEntryDraft`'s argument: a field bound to a
/// `Double` reverts what the user is halfway through typing, so the crossing happens once, on
/// confirm, and it is ``Localization/LocalizedNumberField``'s.
///
/// **The date is the day the number takes effect, not the day it was typed.** The author's plan
/// file announces a week's training max at the week's start, and `FR-16.7.1` reads a session's
/// loads against whatever was in force on *its* day — so a number entered on Wednesday for Monday
/// has to be able to say so. Stored as the start of its day, since
/// ``RepositoryInterface/TrainingMaxRepository/trainingMax(forExerciseID:on:)`` compares `<=`.
///
/// **The note is free text and stays free text.** `FR-16.7.2` writes it "`coach`, or a free note",
/// and "block 3, coach" has no case to become.
struct TrainingMaxDraft: Equatable {
    /// The identity the new history entry takes when this form is saved.
    ///
    /// Minted once with the draft rather than at each save, on `BodyweightEntryDraft`'s rule: the
    /// save is `async` and a second tap would otherwise insert a second row.
    let newEntryID: UUID

    /// The unit ``weightText`` is read in — the user's display preference (`G-3.1`).
    let unit: MassUnit

    /// The locale the field is parsed against (`G-3.4`).
    let locale: Locale

    /// The number, as typed.
    var weightText: String = ""

    /// The day the number takes effect. Today unless the user backdates it.
    var effectiveFrom: Date

    /// Why it changed — `coach`, or whatever the lifter wrote. Empty is allowed and common.
    var reason: String = ""

    /// Which days a date belongs to (`G-3.4`).
    let calendar: Calendar

    /// An empty draft, effective from `day`.
    ///
    /// - Parameters:
    ///   - unit: The unit the number is entered in.
    ///   - locale: The locale the field is parsed against.
    ///   - calendar: Whose days the date is snapped to.
    ///   - day: What the date starts on. Defaults to now.
    ///   - newEntryID: The identity a saved entry takes. Pass the draft's own to re-seed a form the
    ///     user has already opened.
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
        self.effectiveFrom = day
        self.newEntryID = newEntryID
    }

    /// What was typed, as a weight, or `nil` when this locale reads it as no number at all.
    var weight: Weight? {
        LocalizedNumberField.weight(weightText, in: unit, locale: locale)
    }

    /// Whether the user has typed nothing yet — a form nobody has touched has done nothing wrong,
    /// so it is not refused at.
    var isBlank: Bool {
        weightText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Why this will not save, or `nil` when it will.
    var refusal: TrainingMaxDraftRefusal? {
        guard let weight else { return .notAWeight }
        return weight.grams > 0 ? nil : .notPositive
    }

    /// Whether the save command is offered.
    var isSavable: Bool { refusal == nil }

    /// The day the number takes effect, snapped to the start of its day.
    var effectiveDay: Date {
        calendar.startOfDay(for: effectiveFrom)
    }

    /// The note, with the whitespace a keyboard leaves behind taken off.
    ///
    /// **Trimmed rather than validated.** An empty reason is the ordinary case — most changes need
    /// no explaining — and a note that is one space is the same statement as no note at all.
    var trimmedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
