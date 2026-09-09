import Foundation
import PowerliftingCore
import RepositoryInterface

/// One day of the week as the editor holds it (`FR-17.10.1`, `FR-17.10.2`).
///
/// **A day *is* a routine row and the week *is* a program row**, which is why this carries both
/// identifiers: the `ProgramDay` is what orders the week and what a removal takes out, and the
/// `Routine` is what holds the name and the exercises.
public struct WeekEditorDay: Identifiable, Equatable {
    /// The ``RepositoryInterface/ProgramDay`` this is — the day's own identity in the week.
    public let id: UUID

    /// The routine trained on it.
    let routineID: UUID

    /// That routine's name, or `nil` where it has been archived (`FR-15.2.5`).
    ///
    /// **`nil` rather than a stand-in sentence**, on `ProgramDayRow`'s rule: an archived routine is
    /// a day the lifter has to repoint or drop, and a name it does not have is not copy this type
    /// can write.
    var name: String?

    /// The day's exercises, in the order they are drawn and stored.
    var slots: [RoutineSlotDraft]
}

/// The one editor routines and programs collapsed into: the current week's name, its days in
/// order, each day's exercises and each exercise's targets (`FR-17.10`, `D-17.9`).
///
/// **App-lifetime rather than screen-lifetime**, for the reason the routine editor this replaces
/// was: adding an exercise pushes the catalogue as a chooser
/// (``AppNavigation/ExerciseLibraryRoute/routineExercisePicker``), which is `ExerciseLibrary`'s
/// screen and which `TR-1.3` forbids this module from importing — so the app target composes the
/// chooser over this store, and a store created with the screen could not be written into from a
/// screen pushed on top of it.
///
/// **The name is a draft held to Save; everything else is written straight through**
/// (`T-16.15`'s split). Text is typed and a half-typed name is not a fact about the week; a day
/// added, an exercise chosen or a target prescribed is a decision the lifter has made, and holding
/// those in a draft would mean a lifter who planned three days and left had planned none.
///
/// **A target is written through the moment it resolves, and not before.** Three number fields
/// pass through states that cannot be stored on the way to states that can — a reps field being
/// retyped is empty for a keystroke, and `RoutineTargetGroup.targetReps` is not optional — so
/// "written straight through" has to mean *once it is a target*. A group that has never resolved
/// is in no table; one that has, and is then emptied, keeps the row it last wrote and shows the
/// stored value again on the next read. The one field exempt is the load: blank is a *prescribed*
/// blank (`FR-15.2.2`), so it stores as `nil` rather than refusing.
///
/// **The program row and its run are written together, the first time anything on a new week is**
/// (`FR-17.10.2`). There is no program list to make one current from, so **Make current** is the
/// first write: a lifter who plans three days and goes back finds a week, not a plan waiting to be
/// adopted (`DOD-17.9`).
@Observable
public final class WeekEditorState {
    /// What the screen has to show, as one value rather than three flags.
    public enum Phase: Sendable, Equatable {
        /// Nothing has been read yet. ``open(screen:)`` moves out of this.
        case idle

        /// A read is in flight.
        case loading

        /// The week is populated and editable. **A week with no program yet is `ready`** — the
        /// screen authoring one is not a screen that failed to find one.
        case ready

        /// The read failed, carrying the error's description — a diagnostic, not copy (`G-3.4`).
        case failed(String)
    }

    /// The screen's read state.
    public private(set) var phase: Phase = .idle

    /// What is in the name field — the one property here the lifter moves without storing.
    public var name = "" { didSet { retireFailures(name != oldValue) } }

    /// The name the record last held, which is what ``hasUnsavedName`` compares against.
    private(set) var storedName = ""

    /// The days, in ``RepositoryInterface/ProgramDay/order``.
    public internal(set) var days: [WeekEditorDay] = []

    /// Which day is unfolded, or `nil` where every one is collapsed.
    ///
    /// **One at a time, which is the shape a six-day week needs**: thirty-six rows of three fields
    /// open at once is a screen nobody can find their place on, and at `accessibility3` it is one
    /// no reference can even be recorded of (`TR-1.12`'s height limit).
    ///
    /// It is also which day the exercise chooser adds to — see ``addExercise(id:)``.
    public var openDayID: UUID?

    /// Whether the last write changed nothing because the store refused.
    ///
    /// **One flag rather than one per command**, on the argument the program editor this replaces
    /// made: every write here fails the same way and asks for the same thing.
    public private(set) var writeFailed = false

    /// Whether the last **Save** was refused because the week's own name field was empty.
    ///
    /// **Beside ``writeFailed`` rather than a case of it**, on the split the retired routine
    /// editor's failure type made: one names a field the lifter can fill in, the other names only
    /// the store.
    ///
    /// **And beside ``dayNameRequired`` rather than shared with it**, which is a correction: one
    /// flag for both refusals meant the screen said *both* sentences whenever either applied, so
    /// refusing a blank week name also claimed a day had not been renamed. Two refusals that name
    /// two different fields are two flags, whatever they have in common.
    public private(set) var nameRequired = false

    /// Whether the last **Rename** of a day was refused for holding no name.
    ///
    /// Drawn above the days rather than under the name field, which is where the field it names
    /// is — see ``nameRequired`` for why the two are not one flag.
    public private(set) var dayNameRequired = false

    /// The unit loads are entered in — the user's display preference (`G-3.1`, `G-3.2`).
    public private(set) var unit: MassUnit = .kilograms

    /// The locale every field is parsed and rendered against (`G-3.4`).
    public var locale: Locale = .autoupdatingCurrent

    /// The program in force, or `nil` where this week has not been written yet.
    var programID: UUID?

    /// The target groups the store actually holds — the set a delete may name and a reorder may
    /// rewrite. A group the lifter has added and not yet filled in is in no table.
    var persistedGroupIDs: Set<UUID> = []

    /// The screen the reading in hand belongs to. See ``open(screen:)``.
    private var openedScreen: UUID?

    /// The programs, their days and the run in force.
    let programs: any ProgramRepository

    /// The routines the days are, their slots and their targets.
    let routines: any RoutineRepository

    /// The catalogue a slot names.
    let catalogue: any ExerciseRepository

    /// Where ``unit`` comes from.
    private let settings: any SettingsRepository

    /// Builds the editor over the four repositories a week is assembled from.
    ///
    /// - Parameters:
    ///   - programs: The programs, their days and the run in force.
    ///   - routines: The routines those days are.
    ///   - catalogue: Where a slot's exercise name comes from (`FR-1.14.2`).
    ///   - settings: Where ``unit`` comes from.
    public init(
        programs: any ProgramRepository,
        routines: any RoutineRepository,
        catalogue: any ExerciseRepository,
        settings: any SettingsRepository
    ) {
        self.programs = programs
        self.routines = routines
        self.catalogue = catalogue
        self.settings = settings
    }

    // MARK: - Opening

    /// Reads the week, unless the same screen already has it read.
    ///
    /// **The screen token is what makes an app-lifetime store safe behind a screen-lifetime
    /// `.task`**, which is the retired routine editor's rule inherited whole: SwiftUI
    /// re-runs `.task` whenever the view's identity is re-established — while the exercise chooser
    /// is pushed over this screen, for one — and a second read there would throw away the group the
    /// lifter is halfway through typing and the slot the chooser has just added.
    ///
    /// - Parameter screen: The asking screen's own identity, stable for as long as it is alive.
    public func open(screen: UUID) async {
        if openedScreen == screen, phase != .idle { return }
        openedScreen = screen
        await load()
    }

    /// Reads the week: the unit, the run in force, its program, and every day under it.
    ///
    /// **An unsaved name survives a re-read**, on `SessionNoteDraft.follow(_:)`'s rule: every write
    /// on this screen re-reads, and a read that overwrote the field would drop whatever had been
    /// typed since a day was added.
    public func load() async {
        if phase == .loading { return }
        let hadUnsavedName = hasUnsavedName
        phase = .loading
        writeFailed = false
        nameRequired = false
        dayNameRequired = false
        do {
            unit = try await settings.settings().displayUnit
            let run = try await programs.currentRun()
            let program =
                if let run {
                    try await programs.program(id: run.programID, includingDeleted: false)
                } else {
                    Program?.none
                }
            guard let program else {
                // No run, or a run whose program has gone: this screen authors one. `programID`
                // stays nil until the first write, which is what makes Make current implicit.
                programID = nil
                days = []
                persistedGroupIDs = []
                storedName = String(localized: RoutinesStrings.weekEditorDefaultName)
                if !hadUnsavedName { name = storedName }
                phase = .ready
                return
            }
            programID = program.id
            storedName = program.name
            if !hadUnsavedName { name = program.name }
            days = try await readDays(ofProgramID: program.id)
            phase = .ready
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Reads again after a failure.
    public func reload() async {
        guard case .failed = phase else { return }
        await load()
    }

    /// Every day of the program with its exercises and their targets.
    ///
    /// **A day whose routine has been archived is kept and drawn nameless** (`T-16.15`'s rule): the
    /// day is part of the week whether or not the routine behind it survives, and sweeping it would
    /// silently shorten the plan.
    ///
    /// - Parameter programID: The program in force.
    /// - Returns: The days, in order.
    /// - Throws: Whatever the repositories throw.
    private func readDays(ofProgramID programID: UUID) async throws -> [WeekEditorDay] {
        var read: [WeekEditorDay] = []
        var persisted: Set<UUID> = []
        for day in try await programs.days(forProgramID: programID, includingDeleted: false) {
            let routine = try await routines.routine(id: day.routineID, includingDeleted: false)
            var slots: [RoutineSlotDraft] = []
            let stored = try await routines.exercises(
                forRoutineID: day.routineID, includingDeleted: false)
            for slot in stored {
                let groups = try await routines.targetGroups(
                    forRoutineExerciseID: slot.id, includingDeleted: false)
                persisted.formUnion(groups.map(\.id))
                let exercise = try await catalogue.exercise(
                    id: slot.exerciseID, includingDeleted: true)
                slots.append(
                    RoutineSlotDraft(
                        id: slot.id,
                        exerciseID: slot.exerciseID,
                        // A slot naming a row that is not there is drawn BROKEN rather than
                        // dropped, which is the active session's rule for the same situation.
                        name: exercise?.displayName(in: nameLanguage) ?? "",
                        groups: groups.map { RoutineGroupDraft($0, unit: unit, locale: locale) }))
            }
            read.append(
                WeekEditorDay(
                    id: day.id, routineID: day.routineID, name: routine?.name, slots: slots))
        }
        persistedGroupIDs = persisted
        return read
    }

    /// Which of an exercise's two names a row shows (`FR-1.14.2`), from ``locale``.
    var nameLanguage: ExerciseNameLanguage { ExerciseNameLanguage(locale) }

    // MARK: - The week's name

    /// The name as it would be stored: trimmed, so a field holding only spaces is an empty name.
    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the field differs from what the record holds.
    public var hasUnsavedName: Bool { trimmedName != storedName }

    /// Stores the week's name (`FR-17.10.1`).
    ///
    /// **An empty name is refused**, which is where this parts company with the program editor it
    /// replaces. That screen had a list row carrying a day count beside the name; this one is the
    /// only writer of the heading Train's root draws over the week, and a week with no name at all
    /// leaves that heading blank with nothing to explain it.
    public func saveName() async {
        let trimmed = trimmedName
        guard !trimmed.isEmpty else {
            nameRequired = true
            return
        }
        do {
            let week = try await ensureWeek()
            guard let program = try await programs.program(id: week.id, includingDeleted: false)
            else {
                await load()
                return
            }
            // Rebuilt whole because `Program` is immutable, and every column but the name is the
            // original's — the note included, which this screen does not expose (`FR-17.10.1`).
            try await programs.save(
                Program(
                    id: program.id,
                    createdAt: program.createdAt,
                    updatedAt: program.updatedAt,
                    deletedAt: program.deletedAt,
                    name: trimmed,
                    notes: program.notes))
        } catch {
            writeFailed = true
            return
        }
        await load()
    }

    /// The program this week is, writing it and starting its run where there is none
    /// (`FR-17.10.2`, `FR-17.10.3`).
    ///
    /// **The run is started with the program row, not on a later Save.** `FR-17.10.2` makes
    /// **Make current** implicit and `DOD-17.9` says what that has to mean: Plan your week, three
    /// days, back, and This week reads three not-started cards. `WeekState` reads the *run*, so a
    /// program written without one would leave the lifter looking at the empty state they had just
    /// filled in.
    ///
    /// **It writes ``storedName``, never the field.** The field is a draft (see the type's note),
    /// and a program created by adding a day must not adopt a name the lifter has not saved.
    ///
    /// - Returns: The program in force, and whether this call is what wrote it.
    /// - Throws: Whatever the program repository throws.
    private func ensureWeek() async throws -> (id: UUID, created: Bool) {
        if let programID { return (programID, false) }
        let now = Date.now
        let created = UUID()
        try await programs.save(
            Program(
                id: created,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                name: storedName,
                notes: ""))
        try await programs.startRun(
            ProgramRun(
                id: UUID(),
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                programID: created,
                startedAt: now,
                endedAt: nil,
                weekNumber: 1,
                nextDayIndex: 0))
        programID = created
        return (created, true)
    }

    /// The program row, written where this week has none yet — the seam every write-through
    /// command goes through.
    ///
    /// **It reports whether it wrote the week**, which is what a command that fails part-way
    /// needs to know: a program and a started run created for a day that never landed are a week
    /// the lifter did not ask for, and Train's root would draw it in place of **Plan your week**.
    ///
    /// - Returns: The program in force, and whether this call is what wrote it.
    /// - Throws: Whatever the program repository throws.
    func week() async throws -> (id: UUID, created: Bool) { try await ensureWeek() }

    /// Takes back a week this call had to create for a write that then failed (`FR-17.10.2`).
    ///
    /// **The program alone, because the delete cascades** to the days and to the run started with
    /// it — so a refused **Add day** on a fresh install leaves the lifter on the empty state they
    /// were looking at, rather than on a current week with no days in it.
    ///
    /// - Parameter week: What ``week()`` answered. A week that was already there is left alone.
    func discardWeekIfJustCreated(_ week: (id: UUID, created: Bool)) async {
        guard week.created else { return }
        // A cleanup that fails leaves what the caller is about to report anyway (`writeCopy`'s
        // rule, one file over).
        try? await programs.deleteProgram(id: week.id)
        programID = nil
    }

    // MARK: - Diagnostics

    /// Retires a stale refusal when a field actually changes.
    ///
    /// **``dayNameRequired`` is not retired here**, and that is the point of it being its own
    /// flag: typing in the week's name field says nothing about a day whose rename was refused.
    ///
    /// - Parameter changed: Whether the assignment moved the field. `@Observable` cannot tell a
    ///   write from a change, and a `didSet` that fired on either would retire the sentence on a
    ///   binding rewriting the same value.
    private func retireFailures(_ changed: Bool) {
        if changed {
            writeFailed = false
            nameRequired = false
        }
    }

    /// Records that a write landed, for the commands that do not re-read.
    func writeDidLand() {
        writeFailed = false
        nameRequired = false
        dayNameRequired = false
    }

    /// Records that a write was refused.
    func writeDidFail() { writeFailed = true }

    /// Records that a day's rename was refused for being empty.
    func dayNameWasRequired() { dayNameRequired = true }
}
