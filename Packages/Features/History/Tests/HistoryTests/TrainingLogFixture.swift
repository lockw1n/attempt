import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface

@testable import History

/// A store with training in it, written through the real fakes rather than handed to the state.
///
/// **Written, not stubbed.** The session list's whole job is to read three levels joined by `UUID`
/// columns and reduce them to four numbers; a fake that returned what a test handed it would agree
/// with any arithmetic at all, including the wrong one.
struct TrainingLog {
    /// The five fakes over one store.
    let repositories: InMemoryRepositoryStack

    /// The exercises the entries name, in the order they were seeded.
    private(set) var catalogue: [Exercise] = []

    /// A store with an empty catalogue and nothing logged.
    init() {
        repositories = InMemoryRepositoryStack()
    }

    /// Adds an exercise to the catalogue.
    ///
    /// - Parameters:
    ///   - name: What it is called — the string a summary line shows.
    ///   - ukrainian: Its Ukrainian name (`FR-1.14.2`), where the test is about which of the two a
    ///     summary carries. Absent, the row falls back to `name` in either language.
    ///   - archived: Whether it has been retired (`FR-1.1.5`).
    /// - Returns: The record.
    @discardableResult
    mutating func exercise(
        named name: String, ukrainian: String? = nil, archived: Bool = false
    ) async throws -> Exercise {
        let exercise = Self.exercise(named: name, ukrainian: ukrainian, archived: archived)
        try await repositories.exercises.save(exercise)
        catalogue.append(exercise)
        return exercise
    }

    /// One exercise as a value, written to nothing.
    ///
    /// A repository's `save` is keyed on the identifier, so two rows sharing one is a shape no store
    /// here will hold — and `G-2.5` is what says a real one may. This is how a test builds the pair.
    ///
    /// - Parameters:
    ///   - id: Its identifier.
    ///   - name: What it is called.
    ///   - archived: Whether it has been retired (`FR-1.1.5`).
    ///   - deleted: Whether it has been soft-deleted (`G-1.3`). Honoured only by a double that
    ///     models a foreign store: a repository's `save` drops `deletedAt` on the way in, and
    ///     `ExerciseRepository` has no delete, so no local write produces this.
    /// - Returns: The value.
    static func exercise(
        id: UUID = UUID(),
        named name: String,
        ukrainian: String? = nil,
        archived: Bool = false,
        deleted: Bool = false
    ) -> Exercise {
        Exercise(
            id: id,
            createdAt: epoch,
            updatedAt: epoch,
            deletedAt: deleted ? epoch : nil,
            name: name,
            ukrainianName: ukrainian,
            movement: .squat,
            parentExerciseID: nil,
            equipment: .barbell,
            laterality: .bilateral,
            barType: .standard,
            implementCount: 1,
            isCustom: true,
            isArchived: archived,
            notes: "",
            manualE1RM: nil)
    }

    /// Writes one session.
    ///
    /// - Parameters:
    ///   - day: How many days before the fixture's epoch it was trained. Larger is older.
    ///   - notes: The session note (`FR-1.2.9`).
    ///   - isFinished: Whether it was ever ended. `false` leaves `endedAt` null — a workout still
    ///     being logged, which the list carries like any other.
    /// - Returns: The record.
    @discardableResult
    func session(
        daysAgo day: Int,
        notes: String = "",
        isFinished: Bool = true,
        program: (week: Int, dayIndex: Int)? = nil
    ) async throws -> WorkoutSession {
        let session = Self.session(
            daysAgo: day, notes: notes, isFinished: isFinished, program: program)
        try await repositories.workouts.save(session)
        return session
    }

    /// One session as a value, written to nothing — ``exercise(id:named:archived:deleted:)``'s
    /// reason, one level up.
    ///
    /// - Parameters:
    ///   - id: Its identifier.
    ///   - day: How many days before the fixture's epoch it was trained. Larger is older.
    ///   - notes: The session note (`FR-1.2.9`).
    ///   - isFinished: Whether it was ever ended.
    /// - Returns: The value.
    static func session(
        id: UUID = UUID(),
        daysAgo day: Int,
        notes: String = "",
        isFinished: Bool = true,
        program: (week: Int, dayIndex: Int)? = nil
    ) -> WorkoutSession {
        let date = epoch.addingTimeInterval(-Double(day) * 86_400)
        return WorkoutSession(
            id: id,
            createdAt: date,
            updatedAt: date,
            deletedAt: nil,
            date: date,
            startedAt: date,
            endedAt: isFinished ? date.addingTimeInterval(3_600) : nil,
            notes: notes,
            bodyweight: nil,
            programRunID: program == nil ? nil : UUID(),
            scheduledWorkoutID: nil,
            weekNumber: program?.week,
            dayIndex: program?.dayIndex
        )
    }

    /// Adds one exercise to a session.
    ///
    /// - Parameters:
    ///   - exercise: What was performed.
    ///   - session: The session it was performed in.
    ///   - order: Its position within that session.
    /// - Returns: The entry, which is what sets are logged against.
    @discardableResult
    func entry(
        _ exercise: Exercise, in session: WorkoutSession, order: Int = 0
    ) async throws -> ExerciseEntry {
        let entry = ExerciseEntry(
            id: UUID(),
            createdAt: session.date,
            updatedAt: session.date,
            deletedAt: nil,
            sessionID: session.id,
            exerciseID: exercise.id,
            order: order,
            notes: ""
        )
        try await repositories.workouts.save(entry)
        return entry
    }

    /// Logs one set against an entry.
    ///
    /// - Parameters:
    ///   - entry: What it was performed under.
    ///   - order: Its position within that entry.
    ///   - kilograms: The load on one implement, in whole kilograms.
    ///   - reps: Repetitions performed.
    ///   - isWarmup: Whether it was a warmup (`G-1.8`).
    ///   - isCompleted: Whether it was actually performed (`G-1.8`).
    ///   - notes: The set's own note (`FR-1.2.3`) — what `FR-1.5.4`'s search looks in.
    /// - Returns: The record.
    @discardableResult
    func set(
        in entry: ExerciseEntry,
        order: Int = 0,
        kilograms: Int,
        reps: Int,
        isWarmup: Bool = false,
        isCompleted: Bool = true,
        notes: String = ""
    ) async throws -> SetEntry {
        let set = SetEntry(
            id: UUID(),
            createdAt: Self.epoch,
            updatedAt: Self.epoch,
            deletedAt: nil,
            entryID: entry.id,
            order: order,
            weight: Weight(grams: kilograms * 1_000),
            reps: reps,
            rpe: nil,
            rir: nil,
            isWarmup: isWarmup,
            isCompleted: isCompleted,
            targetWeight: nil,
            targetReps: nil,
            modifiers: [],
            notes: notes,
            completedAt: nil
        )
        try await repositories.workouts.save(set)
        return set
    }

    /// Writes one session on an explicit day.
    ///
    /// The day-arithmetic cases need dates named rather than counted: "the last day of December"
    /// is not a number of days before the fixture's epoch, and writing it as one is how a test
    /// stops asserting what it was written to assert.
    ///
    /// - Parameters:
    ///   - date: When it was trained. Stored verbatim, **not** normalised to a day start — a row
    ///     that arrived by sync or restore was not written by this app and need not be one.
    ///   - notes: The session note (`FR-1.2.9`).
    ///   - enteredOn: When the row was created. Later than `date` is `FR-1.2.1`'s backdating.
    /// - Returns: The record.
    @discardableResult
    func session(
        on date: Date, notes: String = "", enteredOn: Date? = nil
    ) async throws -> WorkoutSession {
        let created = enteredOn ?? date
        let session = WorkoutSession(
            id: UUID(),
            createdAt: created,
            updatedAt: created,
            deletedAt: nil,
            date: date,
            startedAt: date,
            endedAt: date.addingTimeInterval(3_600),
            notes: notes,
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil
        )
        try await repositories.workouts.save(session)
        return session
    }

    /// The calendar screen's state, over this store.
    ///
    /// - Parameters:
    ///   - calendar: The calendar the grid and the day index are computed in.
    ///   - today: The instant the screen opens on.
    ///   - workouts: The workout repository to read through, for the cases that need one that
    ///     refuses. Defaults to this store's own.
    /// - Returns: A fresh state that has read nothing yet.
    func calendarState(
        calendar: Calendar = TrainingLog.utc,
        today: Date,
        workouts: (any WorkoutRepository)? = nil
    ) -> CalendarState {
        CalendarState(
            workouts: workouts ?? repositories.workouts,
            exercises: repositories.exercises,
            settings: repositories.settings,
            calendar: calendar,
            today: today
        )
    }

    /// Switches the stored display unit (`G-3.1`).
    ///
    /// The settings row is a single record with ten columns and no `with`-style copy, so changing
    /// one field means restating the other nine. Doing that once here is what keeps a test about
    /// the unit from being nine lines about everything else.
    ///
    /// - Parameter unit: What loads should read in.
    func setDisplayUnit(_ unit: MassUnit) async throws {
        let stored = try await repositories.settings.settings()
        try await repositories.settings.save(
            UserSettings(
                id: stored.id,
                createdAt: stored.createdAt,
                updatedAt: stored.updatedAt,
                deletedAt: stored.deletedAt,
                userID: stored.userID,
                displayUnit: unit,
                e1RMFormula: stored.e1RMFormula,
                theme: stored.theme,
                defaultRoundingIncrement: stored.defaultRoundingIncrement,
                defaultRoundingStrategy: stored.defaultRoundingStrategy
            ))
    }

    /// A Gregorian calendar in UTC, weeks starting on Sunday.
    ///
    /// **Pinned rather than `.current`**, for the reason every snapshot here pins its locale: the
    /// running machine decides both the time zone and the first weekday, so a grid asserted against
    /// `Calendar.current` asserts whatever that machine is set to.
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.firstWeekday = 1
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// A calendar one hour behind UTC, otherwise ``utc``.
    ///
    /// The time zone is what makes a day start move: an instant just after midnight in UTC is the
    /// previous day here.
    static var oneHourBehind: Calendar {
        var calendar = utc
        calendar.timeZone = TimeZone(secondsFromGMT: -3_600) ?? .gmt
        return calendar
    }

    /// A named day, in `calendar`, at its start.
    ///
    /// - Parameters:
    ///   - year: The year.
    ///   - month: The month, 1-based.
    ///   - day: The day of the month.
    ///   - hour: The hour within it. Zero — the day's start — unless a case is about an instant
    ///     that lands on a different day in another time zone.
    ///   - calendar: The calendar to resolve it in.
    /// - Returns: The instant.
    static func day(
        _ year: Int, _ month: Int, _ day: Int, hour: Int = 0, in calendar: Calendar = utc
    ) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? epoch
    }

    /// The app's one recompute actor, over these fakes — what a workout ended here announces to.
    var records: PersonalRecordRecomputer {
        PersonalRecordRecomputer(
            workouts: repositories.workouts, cache: repositories.personalRecords)
    }

    /// The state under test, over this store.
    ///
    /// - Parameter workouts: The workout repository to read through, for the cases that need one
    ///   that refuses. Defaults to this store's own.
    /// - Returns: A fresh state that has read nothing yet.
    func listState(workouts: (any WorkoutRepository)? = nil) -> SessionListState {
        SessionListState(
            workouts: workouts ?? repositories.workouts,
            exercises: repositories.exercises,
            settings: repositories.settings,
            records: records
        )
    }

    /// The search mode's state, over this store.
    ///
    /// - Parameter workouts: The workout repository to read through, for the cases that need one
    ///   that refuses. Defaults to this store's own.
    /// - Returns: A fresh state that has read nothing yet.
    func searchState(workouts: (any WorkoutRepository)? = nil) -> SessionSearchState {
        SessionSearchState(
            workouts: workouts ?? repositories.workouts,
            exercises: repositories.exercises,
            settings: repositories.settings
        )
    }

    /// The fixture's "now" — a fixed instant, so no assertion here depends on the day it runs.
    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)
}
