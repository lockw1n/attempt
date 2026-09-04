import Foundation
import RepositoryInterface
import SwiftData

/// Where the store lives.
///
/// `G-2.2` makes the local store the single source of truth, so this is the whole of the choice —
/// there is no remote option to add later, and no repository in this module performs network I/O.
public enum StoreLocation: Sendable {
    /// SwiftData's own default location for the app.
    case applicationDefault

    /// A store file the caller owns, including its `-shm` and `-wal` siblings.
    case file(URL)

    /// A store that exists for the lifetime of the container and is never written to disk.
    case inMemory
}

/// The repositories over one store, and `G-1.3`'s purge — the only things this module exposes
/// (`TR-0.4.2`, `TR-0.1.2`, `TR-1.14`).
///
/// **`ModelContainer` does not appear in this type's surface, and that is the point.** Every
/// implementation is `internal`, so a consumer cannot name a SwiftData-backed type even
/// deliberately: `TR-0.1.2` is held by the compiler here, exactly as `TR-0.4.3` is held by the
/// entities being `internal`. What a composition root gets is existentials, which is what the
/// protocols were written to be used as.
///
/// **One container, one actor per repository, one context each.** They read each other's writes
/// because a context reads through to the store, and each write lands before the call that made it
/// returns — so nothing here needs a shared context, and a repository cannot see another's
/// half-finished transaction.
public struct PersistenceStack: Sendable {
    /// The exercise catalogue.
    public let exercises: any ExerciseRepository

    /// Each exercise's training-max configuration and history (`TR-16.3`, `FR-16.7`).
    public let trainingMaxes: any TrainingMaxRepository

    /// Sessions, entries, sets — and the targets a routine planned for them (`TR-15.3`).
    ///
    /// **One property answering two protocols**, because it is one actor over one container: a
    /// planned target hangs off an exercise entry, so the delete that cascades into it has to be
    /// the same object's. Two properties would let a caller be handed two stores and write half a
    /// session into each.
    public let workouts: any WorkoutRepository & PlannedTargetRepository

    /// The single settings row (`TR-1.10`).
    public let settings: any SettingsRepository

    /// The bodyweight log.
    public let bodyweight: any BodyweightRepository

    /// The user's equipment profiles.
    public let equipment: any EquipmentRepository

    /// The cached N-rep maxes (`TR-1.6`) — derived values, never truth (`G-1.4`).
    public let personalRecords: any PersonalRecordCacheRepository

    /// Routines, their exercise slots and target groups (`FR-15.2`).
    public let routines: any RoutineRepository

    /// `G-1.3`'s hard deletes, reached through ``purge(_:)`` rather than named directly.
    let purgeRoutine: StorePurge

    /// Opens the store at `location` and builds the repositories over it.
    ///
    /// - Parameters:
    ///   - location: Where the store lives.
    ///   - sync: Whether it mirrors to CloudKit (`FR-1.12.1`). **Defaults to `.disabled`, and every
    ///     caller but the app's own launch path leaves it there** — see ``SyncMode``.
    /// - Throws: ``StoreConfigurationError/inMemoryStoreCannotSync`` where the two arguments
    ///   contradict, otherwise whatever `ModelContainer` throws when the store cannot be opened or
    ///   migrated.
    public init(location: StoreLocation = .applicationDefault, sync: SyncMode = .disabled) throws {
        try self.init(container: makeModelContainer(at: location, sync: sync))
    }

    /// The repositories over a container the caller already has — the seam the tests use.
    init(container: ModelContainer) {
        exercises = SwiftDataExerciseRepository(modelContainer: container)
        trainingMaxes = SwiftDataTrainingMaxRepository(modelContainer: container)
        workouts = SwiftDataWorkoutRepository(modelContainer: container)
        settings = SwiftDataSettingsRepository(modelContainer: container)
        bodyweight = SwiftDataBodyweightRepository(modelContainer: container)
        equipment = SwiftDataEquipmentRepository(modelContainer: container)
        personalRecords = SwiftDataPersonalRecordCacheRepository(modelContainer: container)
        routines = SwiftDataRoutineRepository(modelContainer: container)
        purgeRoutine = StorePurge(modelContainer: container)
    }
}

/// Serialises `ModelContainer` construction across the process.
///
/// **Building two containers concurrently crashes the process**, measured on Swift 6.3.3 at roughly
/// 6% of parallel attempts against 0 of 20 serial ones. It is a SwiftData constraint rather than
/// anything about the data — the stores need not be related, and in-memory ones are not. An app
/// that opens one store at launch never notices; anything that opens a second for an export, a
/// preview or a test does, and the symptom is a signal 11 attributed to whichever entity was added
/// last. The lock lives beside the only call site so the constraint cannot be met by remembering.
let containerLock = NSLock()

/// The container every store in this app is opened through (`TR-0.6.4`, `OUT-0.2`).
///
/// Three things here are deliberate and none of them is the obvious default:
///
/// - **The database is always stated, never left to the default.** The parameter *defaults to
///   `.automatic`*, which means "mirror if the process has a CloudKit entitlement" — so a container
///   left at the default would start mirroring the day a capability was added for some unrelated
///   reason, with nothing in that diff mentioning sync. Passing ``SyncMode`` through means the
///   choice is made by a caller rather than by an entitlement list, and `sync` defaults to
///   `.disabled` so that caller has to ask. `scripts/check-cloudkit.sh` cannot see an omitted
///   argument, which is why the argument is never omitted.
/// - **`Schema(versionedSchema:)`, not a model array.** ``SchemaV1/models`` is the single list of
///   the nine and the CloudKit audit parses it; a container assembled from its own array would be a
///   second list, which is the drift that check exists to prevent. The versioned form also carries
///   the version identifier a migration keys off.
/// - **The migration plan, even though it is measurably inert.** ``AppMigrationPlan`` has no stages,
///   and adding one is not the edit it looks like — that type carries the measured reason, and the
///   crash it produces.
func makeModelContainer(at location: StoreLocation, sync: SyncMode = .disabled) throws -> ModelContainer {
    if case .inMemory = location, sync != .disabled {
        throw StoreConfigurationError.inMemoryStoreCannotSync
    }
    let configuration = makeConfiguration(at: location, sync: sync)

    containerLock.lock()
    defer { containerLock.unlock() }
    return try ModelContainer(
        for: Schema(versionedSchema: SchemaV1.self),
        migrationPlan: AppMigrationPlan.self,
        configurations: configuration
    )
}
