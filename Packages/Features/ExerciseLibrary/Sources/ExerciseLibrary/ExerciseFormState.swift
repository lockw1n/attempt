import Foundation
import PowerliftingCore
import RepositoryInterface

/// Which exercise the form is about (`FR-1.1.3`, `FR-1.1.4`).
///
/// The two are one screen because they are one set of fields over one record; they are two cases
/// rather than an optional identifier because they read differently — creating reads only the
/// catalogue the parent picker offers, and editing has a record that can be missing.
public enum ExerciseFormMode: Sendable, Equatable {
    /// A new custom exercise (`FR-1.1.3`).
    case create

    /// An existing exercise, built-in ones included (`FR-1.1.4`).
    case edit(exerciseID: UUID)
}

/// The create/edit form, as state rather than as a view model (`TR-1.2`, `FR-1.1.3`, `FR-1.1.4`).
///
/// `ExerciseDetailState`'s pattern, including the split it found: ``phase`` is what the screen could
/// read, ``writeFailure`` is what the last save did, and they are separate because a failed save
/// must cost the user neither the form nor what they typed.
///
/// **The fields the form exposes are exactly the fields the detail screen displays** — name,
/// movement, equipment, bar, sides, and the exercise this one varies. `FR-1.1.3` lists five and not
/// ``RepositoryInterface/Exercise/laterality``; the schema carries it with a default and the detail
/// screen renders it as *Sides*, so omitting it here would leave the user looking at a value nothing
/// in the app can change. The two fields on the other side of that line stay off the form for the
/// same test: ``RepositoryInterface/Exercise/notes`` has its own editor on the detail screen, and
/// ``RepositoryInterface/Exercise/implementCount`` is displayed nowhere and keeps the schema's 1.
///
/// **On a built-in exercise all of those but the name are read-only** — see ``catalogueOwnsFields``,
/// which is the one place the rule is stated.
///
/// **An edit rebuilds the record from the one that was read, not from the fields alone.** Everything
/// the form does not expose — the notes, the archive flag, `createdAt`, `isCustom` — is carried
/// across, so saving a rename cannot silently drop a cue the user typed on the detail screen.
@Observable
public final class ExerciseFormState {
    /// What the screen has to show, as one value rather than four flags.
    public enum Phase: Sendable, Equatable {
        /// Nothing has been read yet. ``ExerciseFormState/load()`` moves out of this.
        case idle

        /// A read is in flight.
        case loading

        /// The fields are populated and the form is editable.
        case ready

        /// The identifier resolved to no live exercise. **Terminal**, for
        /// `ExerciseDetailState.Phase.missing`'s reason. Unreachable in ``ExerciseFormMode/create``.
        case missing

        /// The read failed, carrying the error's description.
        ///
        /// A **diagnostic**, not copy (`G-3.4`). **Recoverable**: ``ExerciseFormState/load()`` runs
        /// again from here.
        case failed(String)
    }

    /// The screen's read state.
    public private(set) var phase: Phase = .idle

    /// The last save that failed, as the error's description, or `nil` once one succeeds.
    ///
    /// A **diagnostic**, not copy (`G-3.4`), and deliberately not a ``Phase`` — a failed write
    /// leaves the whole form on screen and the next attempt is another tap.
    public private(set) var writeFailure: String?

    /// Whether a save has landed, which is what the screen leaves on.
    ///
    /// The form does not re-read after a successful write: it is about to be dismissed, and the
    /// screen beneath re-reads for itself. That is also why nothing here has to tell a failed write
    /// from a failed read-after-write — there is no read after the write.
    public private(set) var didSave = false

    /// Whether a save is in flight. It disables ``canSave``, which is what serializes writes:
    /// this is set before the first `await`, so a second tap is refused rather than queued.
    public private(set) var isSaving = false

    /// The exercise's name (`FR-1.1.3`). The one required field.
    public var name: String = "" { didSet { fieldChanged(name != oldValue) } }

    /// Which lift this is a form of. Defaults to the schema's `.other`, which claims nothing.
    public var movement: Movement = .other { didSet { fieldChanged(movement != oldValue) } }

    /// What it is performed with. Defaults to the schema's `.other`.
    public var equipment: Equipment = .other { didSet { fieldChanged(equipment != oldValue) } }

    /// The bar's category. Defaults to the schema's `.other` — not `.standard`, which would assert
    /// something about equipment the user has not chosen.
    public var barType: BarType = .other { didSet { fieldChanged(barType != oldValue) } }

    /// How many sides a rep works. Defaults to the schema's `.bilateral`.
    public var laterality: Laterality = .bilateral { didSet { fieldChanged(laterality != oldValue) } }

    /// The exercise this one varies (`FR-1.1.7`), or `nil` for a root exercise.
    public var parentExerciseID: UUID? {
        didSet { fieldChanged(parentExerciseID != oldValue) }
    }

    /// Whether the parent picker offers every movement's exercises rather than only ``movement``'s.
    ///
    /// **Off by default, and it narrows rather than restricts.** A variation almost always trains
    /// the same lift as what it varies, and 116 candidates is a picker nobody reads; but nothing in
    /// `FR-1.1.7` says a variation may not cross movements, so the wider set is one tap away rather
    /// than unreachable.
    public var offersEveryMovementAsParent = false

    /// Which exercise the form is about.
    public let mode: ExerciseFormMode

    /// The catalogue the parent picker draws on, in read order. Empty until a read lands.
    private var catalogue: [Exercise] = []

    /// The record being edited, as it was read. The fields the form does not expose are carried
    /// from here into the save; `nil` in ``ExerciseFormMode/create``.
    private var editedRecord: Exercise?

    /// The identifier a created exercise gets, minted once when the form is built.
    ///
    /// **Once, not per save.** A write that failed may still have landed — a store that threw after
    /// committing, a sync that raced — and a retry that minted a second identifier would fork the
    /// row rather than upsert it. Unused in ``ExerciseFormMode/edit(exerciseID:)``.
    private let newExerciseID = UUID()

    private let repository: any ExerciseRepository

    /// Builds the form over what it is editing and the repository it reads and writes through.
    ///
    /// - Parameters:
    ///   - mode: Whether this authors a new exercise or edits an existing one.
    ///   - repository: Where the catalogue and the edited record come from.
    public init(mode: ExerciseFormMode, repository: any ExerciseRepository) {
        self.mode = mode
        self.repository = repository
    }

    // MARK: - Reading

    /// Reads what the form needs, on first appearance and on every retry.
    ///
    /// Re-entrant only through ``Phase/loading``, and **also not re-entrant through
    /// ``Phase/ready``** — which matters more here than on a read-only screen: SwiftUI re-runs
    /// `.task` whenever the view's identity is re-established, and a second read that repopulated
    /// the fields would throw away whatever the user had typed since the first.
    ///
    /// Creating reads the catalogue alone, since there is no record to resolve; editing reads the
    /// record too, and reports an identifier that names nothing as ``Phase/missing``.
    public func load() async {
        switch phase {
        case .loading, .ready, .missing: return
        case .idle, .failed: break
        }
        phase = .loading
        do {
            switch mode {
            case .create:
                catalogue = try await repository.exercises(includingDeleted: false)
                phase = .ready
            case .edit(let exerciseID):
                guard
                    let record = try await repository.exercise(
                        id: exerciseID, includingDeleted: false)
                else {
                    phase = .missing
                    return
                }
                catalogue = try await repository.exercises(includingDeleted: false)
                populate(from: record)
                phase = .ready
            }
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    // MARK: - The parent picker (FR-1.1.7)

    /// The exercises this one may be made a variation of, in ``ExerciseOrder``.
    ///
    /// Four exclusions, and each one is a save the repository or the data model would otherwise
    /// have to refuse:
    ///
    /// - **the exercise itself**, which `ExerciseRepository.save(_:)` throws on;
    /// - **its own descendants**, which nothing throws on — a cycle is representable, and a picker
    ///   that offers one is the only way to write one;
    /// - **archived exercises**, because `FR-1.1.5` makes archiving the way an exercise leaves the
    ///   pickers, and this is a picker;
    /// - **other movements' exercises**, unless ``offersEveryMovementAsParent`` says otherwise.
    ///
    /// The parent already stored survives all four: an exercise whose parent was archived, or was
    /// always on another movement, must not lose it because the form could not offer it back.
    public var parentCandidates: [Exercise] {
        let excluded = closure(from: editedRecord?.id)
        return
            catalogue
            .filter { candidate in
                if candidate.id == parentExerciseID { return true }
                guard !excluded.contains(candidate.id), !candidate.isArchived else { return false }
                return offersEveryMovementAsParent || candidate.movement == movement
            }
            .sorted(by: ExerciseOrder.precedes)
    }

    /// The exercise currently chosen as the parent, if one is.
    public var selectedParent: Exercise? {
        parentExerciseID.flatMap { id in catalogue.first { $0.id == id } }
    }

    /// Whether the seed catalogue owns every field below the name (`TR-0.5.1`, `FR-1.1.4`).
    ///
    /// **True for a built-in exercise, and it is why this form will not edit those fields.** The
    /// seed import runs at every launch and is a merge, not a first-run step: on any row whose
    /// ``RepositoryInterface/Exercise/isCustom`` is `false` it re-supplies six columns from the
    /// bundled catalogue — the movement, the parent, the equipment, the laterality, the bar and the
    /// implement count. Five of those are fields this form would otherwise edit, so offering them
    /// would be offering an edit that is accepted, stored, shown, and then undone by the next cold
    /// start with nothing said. The screen shows them as facts instead, and says whose they are.
    ///
    /// **The name is deliberately not one of them.** The merge keeps it precisely so that
    /// `FR-1.1.4`'s rename of a built-in survives an import, which is what makes a built-in
    /// renameable here and otherwise read-only.
    ///
    /// A custom exercise is skipped by that merge altogether, so on one of those every field is the
    /// user's and every field is editable. Creating always authors a custom row, so this is `false`
    /// there too.
    public var catalogueOwnsFields: Bool {
        guard let editedRecord else { return false }
        return !editedRecord.isCustom
    }

    /// `exerciseID` and everything that descends from it — the set a parent may not be drawn from.
    ///
    /// Walks the catalogue rather than recursing through it, so a cycle already stored (an import,
    /// a sync) cannot spin here.
    ///
    /// - Parameter exerciseID: The exercise whose subtree to collect, or `nil` when nothing is being
    ///   edited and so nothing is excluded.
    /// - Returns: The identifiers no parent may be chosen from.
    private func closure(from exerciseID: UUID?) -> Set<UUID> {
        guard let exerciseID else { return [] }
        var collected: Set<UUID> = [exerciseID]
        var added = true
        while added {
            added = false
            for exercise in catalogue where !collected.contains(exercise.id) {
                guard let parentID = exercise.parentExerciseID, collected.contains(parentID) else {
                    continue
                }
                collected.insert(exercise.id)
                added = true
            }
        }
        return collected
    }

    // MARK: - Validation

    /// The name as it would be stored: trimmed, so a field holding only spaces is an empty name.
    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the one required field has been filled in.
    ///
    /// **The only thing that blocks a save.** Every other field carries the schema's own default
    /// (`TR-0.3.1`), so the form asks for a name and nothing else.
    public var isNameValid: Bool { !trimmedName.isEmpty }

    /// Whether the save command is available: a form that has been read, a name, and no save
    /// already running.
    public var canSave: Bool { phase == .ready && isNameValid && !isSaving }

    // MARK: - Writing

    /// Stores the exercise (`FR-1.1.3`, `FR-1.1.4`).
    ///
    /// **The record is built here, when the command is issued** — `ExerciseDetailState.saveNotes()`'s
    /// rule, for the same reason: what gets stored must be what was on screen when the user tapped,
    /// not whatever the fields hold by the time the write reaches the store.
    ///
    /// A rename is a plain field change and needs nothing else: every set is logged against
    /// ``RepositoryInterface/Exercise/id``, and the write path upserts on that id, so history
    /// follows the row rather than the name (`FR-1.1.4`).
    public func save() async {
        guard canSave, let record = record() else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.save(record)
        } catch {
            writeFailure = String(describing: error)
            return
        }
        writeFailure = nil
        editedRecord = record
        didSave = true
    }

    /// What ``save()`` would store, or `nil` if the form is not in a state that can produce one.
    ///
    /// Creating mints the row; editing rebuilds the one that was read, replacing the six exposed
    /// fields and carrying everything else — see the type's own documentation for why that is not
    /// optional.
    private func record() -> Exercise? {
        if let edited = editedRecord {
            // The five seed-owned fields are taken from the record rather than from the form
            // whenever the catalogue owns them, so the rule holds here and not only in the view:
            // a field the screen never offered cannot reach the store by another path.
            let owned = !edited.isCustom
            return Exercise(
                id: edited.id,
                createdAt: edited.createdAt,
                updatedAt: edited.updatedAt,
                deletedAt: edited.deletedAt,
                name: trimmedName,
                movement: owned ? edited.movement : movement,
                parentExerciseID: owned ? edited.parentExerciseID : parentExerciseID,
                equipment: owned ? edited.equipment : equipment,
                laterality: owned ? edited.laterality : laterality,
                barType: owned ? edited.barType : barType,
                implementCount: edited.implementCount,
                isCustom: edited.isCustom,
                isArchived: edited.isArchived,
                notes: edited.notes
            )
        }
        guard case .create = mode else { return nil }
        let now = Date.now
        return Exercise(
            id: newExerciseID,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            name: trimmedName,
            movement: movement,
            parentExerciseID: parentExerciseID,
            equipment: equipment,
            laterality: laterality,
            barType: barType,
            // The schema's own default. It is a factor in `FR-1.5.1`'s tonnage and is displayed on
            // no screen, so a form field for it would be a number the user cannot check.
            implementCount: 1,
            // What `FR-1.1.3` means by "custom", and what stops a seed re-import from overwriting
            // the row (`TR-0.5.1`).
            isCustom: true,
            isArchived: false,
            // The detail screen's editor owns these (`FR-1.1.6`).
            notes: ""
        )
    }

    /// Fills the fields from a record being edited.
    private func populate(from record: Exercise) {
        editedRecord = record
        name = record.name
        movement = record.movement
        equipment = record.equipment
        barType = record.barType
        laterality = record.laterality
        parentExerciseID = record.parentExerciseID
        // A parent on another movement would otherwise vanish from the picker the moment the form
        // opened, which reads as the form having dropped it.
        offersEveryMovementAsParent =
            record.parentExerciseID != nil && selectedParent?.movement != record.movement
    }

    /// Retires a stale ``writeFailure`` when a field actually changes.
    ///
    /// The banner describes one attempt to store one set of values, so the next edit — including one
    /// that puts the old value back — is what ends it. `ExerciseDetailState.notesDraft` has the long
    /// form of the argument.
    ///
    /// - Parameter changed: Whether the assignment moved the field. `@Observable` cannot tell a
    ///   write from a change, and a `didSet` that fired on either would retire the banner on a
    ///   binding rewriting the same value.
    private func fieldChanged(_ changed: Bool) {
        if changed { writeFailure = nil }
    }
}
