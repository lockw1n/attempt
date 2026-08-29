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
    /// The exercise catalogue and each exercise's training-max history.
    public let exercises: any ExerciseRepository

    /// Sessions, entries and sets.
    public let workouts: any WorkoutRepository

    /// The single settings row (`TR-1.10`).
    public let settings: any SettingsRepository

    /// The bodyweight log.
    public let bodyweight: any BodyweightRepository

    /// The user's equipment profiles.
    public let equipment: any EquipmentRepository

    /// The cached N-rep maxes (`TR-1.6`) — derived values, never truth (`G-1.4`).
    public let personalRecords: any PersonalRecordCacheRepository

    /// `G-1.3`'s hard deletes, reached through ``purge(_:)`` rather than named directly.
    let purgeRoutine: StorePurge

    /// Opens the store at `location` and builds the repositories over it.
    ///
    /// - Throws: Whatever `ModelContainer` throws when the store cannot be opened or migrated.
    public init(location: StoreLocation = .applicationDefault) throws {
        try self.init(container: makeModelContainer(at: location))
    }

    /// The repositories over a container the caller already has — the seam the tests use.
    init(container: ModelContainer) {
        exercises = SwiftDataExerciseRepository(modelContainer: container)
        workouts = SwiftDataWorkoutRepository(modelContainer: container)
        settings = SwiftDataSettingsRepository(modelContainer: container)
        bodyweight = SwiftDataBodyweightRepository(modelContainer: container)
        equipment = SwiftDataEquipmentRepository(modelContainer: container)
        personalRecords = SwiftDataPersonalRecordCacheRepository(modelContainer: container)
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
/// - **`cloudKitDatabase: .none`, said out loud.** The parameter *defaults to `.automatic`*, which
///   means "mirror if the process has a CloudKit entitlement". Sync being off today is therefore a
///   property of the entitlement list rather than of any decision in code, and a container left at
///   the default is one capability away from mirroring — added for some unrelated reason, with
///   nothing in that diff mentioning sync. `scripts/check-cloudkit.sh` bans the two enabling
///   spellings but cannot see an omitted argument, so this is the only place the choice is
///   recorded.
/// - **`Schema(versionedSchema:)`, not a model array.** ``SchemaV1/models`` is the single list of
///   the nine and the CloudKit audit parses it; a container assembled from its own array would be a
///   second list, which is the drift that check exists to prevent. The versioned form also carries
///   the version identifier a migration keys off.
/// - **The migration plan, even though it is measurably inert.** ``AppMigrationPlan`` has no stages
///   and while `G-1.7` holds it never will do anything. It is passed so that the day a second
///   version exists the container is already reading the version history, rather than needing an
///   edit at the moment of the first real migration.
func makeModelContainer(at location: StoreLocation) throws -> ModelContainer {
    let configuration: ModelConfiguration
    switch location {
    case .applicationDefault:
        configuration = ModelConfiguration(cloudKitDatabase: .none)
    case .file(let url):
        configuration = ModelConfiguration(url: url, cloudKitDatabase: .none)
    case .inMemory:
        configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    }

    containerLock.lock()
    defer { containerLock.unlock() }
    return try ModelContainer(
        for: Schema(versionedSchema: SchemaV1.self),
        migrationPlan: AppMigrationPlan.self,
        configurations: configuration
    )
}
