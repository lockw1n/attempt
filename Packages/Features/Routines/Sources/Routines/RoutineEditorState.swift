import Foundation
import PowerliftingCore
import RepositoryInterface

/// Which routine the editor is about (`FR-15.2.1`).
///
/// Two cases rather than an optional identifier, for ``RepositoryInterface/Exercise``'s form's
/// reason: they read differently, creating having no record to resolve and editing having one that
/// can be missing.
public enum RoutineEditorMode: Sendable, Equatable {
    /// A routine being authored.
    case create

    /// An existing routine.
    case edit(routineID: UUID)
}

/// The routine editor, as state rather than as a view model (`TR-1.2`, `FR-15.2.1`, `FR-15.2.2`).
///
/// **App-lifetime rather than screen-lifetime, and it is the one store here that has to be.**
/// Adding an exercise pushes the catalogue as a chooser
/// (``AppNavigation/ExerciseLibraryRoute/routineExercisePicker``), which is `ExerciseLibrary`'s
/// screen — `TR-1.3` forbids this module depending on that one, so the app target composes the
/// chooser over this store exactly as it composes the workout's chooser over `ActiveSessionStore`.
/// A store created with the screen could not be written into from a screen pushed on top of it.
///
/// **It holds a draft and writes on save**, unlike the dashboard's tick-through screens. Three
/// levels of records with an order to their writes is not something to commit a keystroke at a
/// time: a routine half-written by a lifter who changed their mind is a routine
/// ``AppNavigation/RoutinesRoute/routineList`` would then list.
///
/// **The save is a diff, not a rewrite.** Slots and groups deleted since the read are soft-deleted
/// by identifier; ones added were never stored and are never deleted. Nothing else can reclaim them
/// — the repository's cascade only runs when a whole routine or slot goes.
@Observable
public final class RoutineEditorState {
    /// What the screen has to show, as one value rather than four flags.
    public enum Phase: Sendable, Equatable {
        /// Nothing has been read yet. ``RoutineEditorState/open(_:)`` moves out of this.
        case idle

        /// A read is in flight.
        case loading

        /// The draft is populated and editable.
        case ready

        /// The identifier resolved to no live routine. **Terminal**: reading again resolves to the
        /// same absence. Unreachable in ``RoutineEditorMode/create``.
        case missing

        /// The read failed, carrying the error's description — a diagnostic, not copy (`G-3.4`).
        /// **Recoverable**: ``RoutineEditorState/reload()`` runs again from here.
        case failed(String)
    }

    /// The screen's read state.
    public private(set) var phase: Phase = .idle

    /// The last save that failed, as the error's description, or `nil` once one succeeds.
    ///
    /// A **diagnostic**, not copy (`G-3.4`), and deliberately not a ``Phase`` — a failed write
    /// leaves the whole draft on screen and the next attempt is another tap.
    public private(set) var writeFailure: String?

    /// Whether a save has landed, which is what the screen leaves on.
    public private(set) var didSave = false

    /// Whether a save is in flight. It disables ``canSave``, which is what serializes writes.
    public private(set) var isSaving = false

    /// The routine's name (`FR-15.2.1`). The one required field outside the groups.
    public var name: String = "" { didSet { retireWriteFailure(name != oldValue) } }

    /// The exercise slots, in the order they are drawn and stored.
    private(set) var slots: [RoutineSlotDraft] = []

    /// Which routine this is about. Set by ``open(_:)``, so the screen and the chooser pushed over
    /// it agree on one answer.
    public private(set) var mode: RoutineEditorMode = .create

    /// The unit loads are entered in — the user's display preference (`G-3.1`, `G-3.2`).
    public private(set) var unit: MassUnit = .kilograms

    /// The locale every field is parsed and rendered against.
    public var locale: Locale = .autoupdatingCurrent

    /// The identifier a created routine gets, minted once per ``open(_:screen:)``. See
    /// ``RoutineGroupDraft/id`` for why it is not minted per save.
    private var newRoutineID = UUID()

    /// The screen the draft in hand belongs to. See ``open(_:screen:)``.
    private var openedScreen: UUID?

    /// The routine as it was read, so a save carries the columns the editor does not expose.
    private var editedRecord: Routine?

    /// The slot identifiers the store held when the draft was read — the set a delete may name.
    private var persistedSlotIDs: Set<UUID> = []

    /// The group identifiers the store held when the draft was read.
    private var persistedGroupIDs: Set<UUID> = []

    private let repository: any RoutineRepository
    private let catalogue: any ExerciseRepository
    private let settings: any SettingsRepository

    /// Builds the editor over the three repositories a routine is three facts from: the routine
    /// itself, the catalogue its slots name, and the settings row that decides what unit a load is
    /// entered in.
    ///
    /// - Parameters:
    ///   - repository: Where routines, slots and groups are read and written.
    ///   - catalogue: Where a slot's exercise name comes from (`FR-1.14.2`).
    ///   - settings: Where ``unit`` comes from.
    public init(
        repository: any RoutineRepository,
        catalogue: any ExerciseRepository,
        settings: any SettingsRepository
    ) {
        self.repository = repository
        self.catalogue = catalogue
        self.settings = settings
    }

    // MARK: - Opening

    /// Points the editor at a routine and reads it, unless the same screen already has it open.
    ///
    /// **The screen token is what makes an app-lifetime store safe behind a screen-lifetime
    /// `.task`.** SwiftUI re-runs `.task` whenever the view's identity is re-established — while
    /// the exercise chooser is pushed over this screen, for one — and a second read there would
    /// throw away everything typed since the first, which is `ExerciseFormState.load()`'s rule and
    /// matters more here because this store outlives the screen.
    ///
    /// **A new push is a new token, and reads again**, which is the half a bare "same mode" guard
    /// gets wrong: nothing writes on the way out of this screen, so a draft the lifter backed out
    /// of is still in the store. Handing it back the next time they open that routine would show
    /// them edits they had abandoned, over a list still showing the stored version, with the save
    /// command armed.
    ///
    /// - Parameters:
    ///   - mode: Which routine to edit, or that a new one is being authored.
    ///   - screen: The asking screen's own identity, stable for as long as that screen is alive.
    public func open(_ mode: RoutineEditorMode, screen: UUID) async {
        if self.mode == mode, openedScreen == screen, phase != .idle { return }
        self.mode = mode
        reset()
        openedScreen = screen
        await read()
    }

    /// Reads again after a failure, keeping the mode.
    public func reload() async {
        guard case .failed = phase else { return }
        await read()
    }

    /// Empties the draft, so an editor opened on a second routine shows nothing of the first.
    private func reset() {
        phase = .idle
        name = ""
        slots = []
        editedRecord = nil
        persistedSlotIDs = []
        persistedGroupIDs = []
        writeFailure = nil
        didSave = false
        newRoutineID = UUID()
    }

    /// Reads the unit, and — when editing — the routine and its three levels.
    private func read() async {
        phase = .loading
        do {
            unit = try await settings.settings().displayUnit
            guard case .edit(let routineID) = mode else {
                phase = .ready
                return
            }
            guard let record = try await repository.routine(id: routineID, includingDeleted: false)
            else {
                phase = .missing
                return
            }
            editedRecord = record
            name = record.name
            slots = try await readSlots(ofRoutineID: routineID)
            persistedSlotIDs = Set(slots.map(\.id))
            persistedGroupIDs = Set(slots.flatMap { $0.groups.map(\.id) })
            phase = .ready
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// The routine's slots with their groups, as drafts.
    ///
    /// **Three reads, not one**, and one more per slot: the repository declares no relationships
    /// (`G-2.5`), so the tree is assembled here rather than returned.
    private func readSlots(ofRoutineID routineID: UUID) async throws -> [RoutineSlotDraft] {
        let stored = try await repository.exercises(
            forRoutineID: routineID, includingDeleted: false)
        var drafts: [RoutineSlotDraft] = []
        for slot in stored {
            let groups = try await repository.targetGroups(
                forRoutineExerciseID: slot.id, includingDeleted: false)
            let exercise = try await catalogue.exercise(
                id: slot.exerciseID, includingDeleted: true)
            drafts.append(
                RoutineSlotDraft(
                    id: slot.id,
                    exerciseID: slot.exerciseID,
                    // A slot naming a row that is not there is drawn BROKEN rather than dropped,
                    // which is the active session's rule for the same situation: a missing name is
                    // visible and a missing row is not.
                    name: exercise?.displayName(in: nameLanguage) ?? "",
                    groups: groups.map { RoutineGroupDraft($0, unit: unit, locale: locale) }
                ))
        }
        return drafts
    }

    /// Which of an exercise's two names a row shows (`FR-1.14.2`), from ``locale``.
    private var nameLanguage: ExerciseNameLanguage {
        ExerciseNameLanguage(locale)
    }

    // MARK: - Editing the draft

    /// Adds an exercise to the end of the routine (`FR-15.2.1`).
    ///
    /// **It reads the catalogue for the name**, which is the one read this command makes: the
    /// chooser that calls it is another module's screen and hands over an identifier, not a record.
    /// A row that cannot be read is added anyway, drawn nameless — refusing it would lose the
    /// lifter's tap over a display string.
    ///
    /// - Parameter exerciseID: The catalogue exercise to prescribe.
    public func addExercise(id exerciseID: UUID) async {
        guard phase == .ready else { return }
        let exercise = try? await catalogue.exercise(id: exerciseID, includingDeleted: false)
        slots.append(
            RoutineSlotDraft(
                id: UUID(),
                exerciseID: exerciseID,
                name: exercise?.displayName(in: nameLanguage) ?? "",
                // One empty group, because a slot with none is a slot with nothing to fill in —
                // FR-15.2.2's blank target is an empty weight, not an absent group.
                groups: [RoutineGroupDraft()]
            ))
        writeFailure = nil
    }

    /// Removes a slot from the draft.
    func removeSlot(at index: Int) {
        guard slots.indices.contains(index) else { return }
        slots.remove(at: index)
        writeFailure = nil
    }

    /// Moves a slot one place towards the front, or does nothing at the front.
    ///
    /// **Explicit controls rather than a drag**, twice over: `TR-1.12`'s `ImageRenderer` harness
    /// rasterises `List`'s `.onMove` as a placeholder, and a drag is the one reorder gesture
    /// VoiceOver and Switch Control cannot perform (`G-4.2`). The active session's cards made the
    /// same call.
    func moveSlotUp(_ index: Int) {
        guard slots.indices.contains(index), index > 0 else { return }
        slots.swapAt(index, index - 1)
        writeFailure = nil
    }

    /// Moves a slot one place towards the back, or does nothing at the back.
    func moveSlotDown(_ index: Int) {
        guard slots.indices.contains(index), index < slots.count - 1 else { return }
        slots.swapAt(index, index + 1)
        writeFailure = nil
    }

    /// Adds an empty target group to a slot (`FR-15.2.1`'s amendment).
    func addGroup(toSlotAt index: Int) {
        guard slots.indices.contains(index) else { return }
        slots[index].groups.append(RoutineGroupDraft())
        writeFailure = nil
    }

    /// Removes one target group. A slot may be left with none — that is a slot with no plan yet,
    /// and it is `canSave`'s business rather than this command's.
    func removeGroup(at groupIndex: Int, fromSlotAt index: Int) {
        guard slots.indices.contains(index), slots[index].groups.indices.contains(groupIndex) else {
            return
        }
        slots[index].groups.remove(at: groupIndex)
        writeFailure = nil
    }

    /// Moves a target group one place towards the top set.
    func moveGroupUp(_ groupIndex: Int, inSlotAt index: Int) {
        guard slots.indices.contains(index), slots[index].groups.indices.contains(groupIndex),
            groupIndex > 0
        else { return }
        slots[index].groups.swapAt(groupIndex, groupIndex - 1)
        writeFailure = nil
    }

    /// Moves a target group one place towards the backoff.
    func moveGroupDown(_ groupIndex: Int, inSlotAt index: Int) {
        guard slots.indices.contains(index), slots[index].groups.indices.contains(groupIndex),
            groupIndex < slots[index].groups.count - 1
        else { return }
        slots[index].groups.swapAt(groupIndex, groupIndex + 1)
        writeFailure = nil
    }

    /// A binding target for one group's fields — the editor's rows write through this rather than
    /// reaching into ``slots``, so every mutation retires a stale write diagnostic.
    func updateGroup(
        at groupIndex: Int, inSlotAt index: Int, _ change: (inout RoutineGroupDraft) -> Void
    ) {
        guard slots.indices.contains(index), slots[index].groups.indices.contains(groupIndex) else {
            return
        }
        let before = slots[index].groups[groupIndex]
        change(&slots[index].groups[groupIndex])
        retireWriteFailure(slots[index].groups[groupIndex] != before)
    }

    // MARK: - Validation

    /// The name as it would be stored: trimmed, so a field holding only spaces is an empty name.
    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether every group in the draft holds a storable prescription.
    ///
    /// A slot with **no** groups passes: `FR-15.2.1` prescribes an ordered list of exercises, and a
    /// lifter who has added one and not yet said what to do with it has authored a routine that is
    /// short rather than wrong.
    public var everyGroupResolves: Bool {
        slots.allSatisfy { slot in
            slot.groups.allSatisfy { $0.isResolvable(unit: unit, locale: locale) }
        }
    }

    /// Whether the save command is available: a draft that has been read, a name, every group
    /// storable, and no save already running.
    public var canSave: Bool {
        phase == .ready && !trimmedName.isEmpty && everyGroupResolves && !isSaving
    }

    // MARK: - Writing

    /// Stores the routine, its slots and their groups (`FR-15.2.1`, `FR-15.2.2`).
    ///
    /// **The write order is the repository's, not a preference**: `save(_ exercise:)` refuses a
    /// slot whose routine does not exist and `save(_ group:)` refuses a group whose slot does not,
    /// so it goes routine → slot → group. Deletions come last, because a slot deleted first would
    /// take its groups with it and a group re-saved after that would be re-saved onto a dead slot.
    ///
    /// A failure part-way leaves the store **partially written** and says so through
    /// ``writeFailure``; the retry is the same command, and every write here is an upsert on an
    /// identifier minted once, so running it again finishes the job rather than forking it. The
    /// deletes are the exception and ``deleteRemoved()`` is where that is handled.
    public func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let now = Date.now
            try await repository.save(routineRecord(at: now))
            try await saveSlots(at: now)
            try await deleteRemoved()
        } catch {
            writeFailure = String(describing: error)
            return
        }
        writeFailure = nil
        didSave = true
    }

    /// The routine row this save stores — the record that was read with its name replaced, or a new
    /// one.
    private func routineRecord(at now: Date) -> Routine {
        guard let editedRecord else {
            return Routine(
                id: newRoutineID, createdAt: now, updatedAt: now, deletedAt: nil, name: trimmedName)
        }
        return Routine(
            id: editedRecord.id,
            createdAt: editedRecord.createdAt,
            updatedAt: editedRecord.updatedAt,
            deletedAt: editedRecord.deletedAt,
            name: trimmedName)
    }

    /// Writes every slot and every group at its draft position, so a reorder is `order` rewritten.
    private func saveSlots(at now: Date) async throws {
        let routineID = editedRecord?.id ?? newRoutineID
        for (index, slot) in slots.enumerated() {
            try await repository.save(
                RoutineExercise(
                    id: slot.id,
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil,
                    routineID: routineID,
                    exerciseID: slot.exerciseID,
                    order: index))
            for (groupIndex, group) in slot.groups.enumerated() {
                try await repository.save(
                    RoutineTargetGroup(
                        id: group.id,
                        createdAt: now,
                        updatedAt: now,
                        deletedAt: nil,
                        routineExerciseID: slot.id,
                        order: groupIndex,
                        // Blank stays blank: `weight(unit:locale:)` answers `nil` to an empty field
                        // and `canSave` has already refused every other way of getting one.
                        targetWeight: group.weight(unit: unit, locale: locale),
                        targetReps: group.reps(locale: locale) ?? 0,
                        targetSets: group.sets(locale: locale) ?? 0))
            }
        }
    }

    /// Soft-deletes what the draft dropped, and only what the store actually holds.
    ///
    /// A slot added and removed inside one editing session was never written, and
    /// `deleteRoutineExercise(id:)` throws `recordNotFound` on one — which would turn a tidy-up
    /// into a failed save.
    ///
    /// **Each success is recorded as it lands**, because a delete is the one write in a save that
    /// is not an upsert: the repository refuses a second delete of a row it has already reclaimed.
    /// A retry after a failure part-way through here would otherwise throw on the rows the first
    /// attempt had already taken, and the routine could never be saved again.
    private func deleteRemoved() async throws {
        let liveGroups = Set(slots.flatMap { $0.groups.map(\.id) })
        for id in persistedGroupIDs.subtracting(liveGroups) {
            try await repository.deleteTargetGroup(id: id)
            persistedGroupIDs.remove(id)
        }
        let liveSlots = Set(slots.map(\.id))
        for id in persistedSlotIDs.subtracting(liveSlots) {
            try await repository.deleteRoutineExercise(id: id)
            persistedSlotIDs.remove(id)
        }
        persistedSlotIDs = liveSlots
        persistedGroupIDs = liveGroups
    }

    /// Retires a stale ``writeFailure`` when a field actually changes.
    ///
    /// - Parameter changed: Whether the assignment moved the field. `@Observable` cannot tell a
    ///   write from a change, and a `didSet` that fired on either would retire the banner on a
    ///   binding rewriting the same value.
    private func retireWriteFailure(_ changed: Bool) {
        if changed { writeFailure = nil }
    }
}
