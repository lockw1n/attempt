import Foundation
import Persistence
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import DerivedValues
@testable import Settings

/// The out-of-band backup this suite measures, and the store it is restored into.
enum RealLogBackup {
    /// The environment variable naming the file.
    nonisolated static let variable = "ATTEMPT_REAL_BACKUP"

    /// The path the author supplied, or `nil` where they supplied none.
    nonisolated static var path: String? {
        guard let named = ProcessInfo.processInfo.environment[variable], !named.isEmpty else {
            return nil
        }
        return named
    }

    /// The file, or `nil` where no path was named.
    nonisolated static var fileURL: URL? { path.map { URL(fileURLWithPath: $0) } }

    /// What to do about it, carried on the trait and printed when the suite is skipped.
    nonisolated static let howToSupplyIt: Comment = """
        Set \(variable) to a full-backup .json file to measure DOD-16.4 and DOD-16.2 over a real \
        training log.
        """

    /// Whether there is a backup to measure.
    nonisolated static var isAvailable: Bool { path != nil }

    /// A real file store in a directory the caller owns and deletes.
    ///
    /// **`PersistenceStack`, never a `ModelContainer` built here** — the stack takes the lock that
    /// stops two concurrent constructions crashing the process, and there is no other supported way
    /// in from outside `Persistence`.
    ///
    /// - Returns: The stack, and the directory holding the store file and its siblings.
    /// - Throws: Whatever the file manager or `ModelContainer` throws.
    static func temporaryStore() throws -> (stack: PersistenceStack, directory: URL) {
        let directory = URL.temporaryDirectory.appending(path: "attempt-real-log-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stack = try PersistenceStack(location: .file(directory.appending(path: "store.sqlite")))
        return (stack, directory)
    }

    /// How many live sets the store holds against each exercise, counted the only way the
    /// repositories allow — through the catalogue, since there is no read that enumerates every set.
    ///
    /// **Per exercise rather than one total**, because the total anchors the restore and the
    /// per-exercise figure is what says how large the input to the asserted recompute was. A bare
    /// duration cannot say that, and `NFR-16.1`'s budget is written against an input size.
    ///
    /// - Parameters:
    ///   - stack: The store.
    ///   - catalogue: Its live exercises.
    /// - Returns: The count for each exercise that has one.
    /// - Throws: Whatever the repository throws.
    static func liveSetCounts(
        in stack: PersistenceStack,
        over catalogue: [Exercise]
    ) async throws -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for exercise in catalogue {
            counts[exercise.id] = try await stack.workouts.sets(
                forExerciseID: exercise.id, includingDeleted: false
            ).count
        }
        return counts
    }

    /// How many live sets the store holds under `entryIDs` — the other join, through the entries the
    /// archive names rather than through the catalogue.
    ///
    /// - Parameters:
    ///   - stack: The store.
    ///   - entryIDs: The archive's own entry identifiers.
    /// - Returns: The total.
    /// - Throws: Whatever the repository throws.
    static func liveSetCount(
        in stack: PersistenceStack, overEntryIDs entryIDs: [UUID]
    ) async throws -> Int {
        var total = 0
        for entryID in entryIDs {
            total += try await stack.workouts.sets(forEntryID: entryID, includingDeleted: false)
                .count
        }
        return total
    }

    /// How many of `archive`'s sets are `FR-16.4.2`'s pending — not completed, in a session the file
    /// left open — and so are stored by a restore but absent from history.
    ///
    /// **Read off the archive rather than off the store**, which is what makes it an independent
    /// account of the difference between the two counts instead of a restatement of one of them.
    ///
    /// - Parameter archive: The decoded backup.
    /// - Returns: The count.
    static func pendingSetCount(in archive: TrainingLogArchive) -> Int {
        let open = Set(archive.sessions.filter { !$0.isFinished }.map(\.id))
        let entrySessions = Dictionary(
            archive.entries.map { ($0.id, $0.sessionID) }, uniquingKeysWith: { first, _ in first })
        return archive.sets.count { set in
            guard !set.isCompleted, let sessionID = entrySessions[set.entryID] else { return false }
            return open.contains(sessionID)
        }
    }

    /// The app's own writer over a real store.
    ///
    /// - Parameters:
    ///   - stack: The store.
    ///   - records: The recompute actor the restore tells about every session it writes.
    /// - Returns: The restore.
    static func restore(
        into stack: PersistenceStack,
        records: PersonalRecordRecomputer
    ) -> StoreRestore {
        StoreRestore(
            exercises: stack.exercises,
            trainingMaxes: stack.trainingMaxes,
            workouts: stack.workouts,
            bodyweight: stack.bodyweight,
            equipment: stack.equipment,
            routines: stack.routines,
            programs: stack.programs,
            settings: stack.settings,
            records: records)
    }

    /// `FR-1.9.1`'s selection for a lifter who has made none, which `.dashboardLifts` resolves to.
    ///
    /// **A mirror of `DashboardDefaults.exerciseIDs(in:mostTrained:)` and not a second decision.**
    /// That type is `internal` to the `Dashboard` feature, and a feature package may not depend on
    /// another one — so the rule cannot be shared with this target without a dependency `T-16.16`'s
    /// scope forbids. It is copied rather than reinvented: root exercise, barbell, from the seed,
    /// not archived, name breaking the tie — and, since `FR-16.5.1`, a candidate the lifter has no
    /// history for replaced by the exercise they train most. If the two ever disagree, this
    /// measurement is scoped to something the dashboard does not tile, and the fix is to move the
    /// rule down a layer.
    ///
    /// - Parameters:
    ///   - catalogue: The exercises to choose from.
    ///   - mostTrained: Every exercise with a completed working set in the lookback window,
    ///     most-trained first.
    /// - Returns: One identifier per movement that had a candidate.
    static func defaultDashboardExerciseIDs(
        in catalogue: [Exercise], mostTrained: [UUID]
    ) -> [UUID] {
        let candidates = [Movement.squat, .bench, .deadlift].map { movement in
            catalogue
                .filter {
                    $0.movement == movement && $0.parentExerciseID == nil
                        && $0.equipment == .barbell && !$0.isCustom && !$0.isArchived
                }
                .min { $0.name < $1.name }?
                .id
        }
        let trained = Set(mostTrained)
        let kept = candidates.map { candidate -> UUID? in
            guard let candidate, trained.contains(candidate) else { return nil }
            return candidate
        }
        let reserved = Set(kept.compactMap { $0 })
        let tileable = Set(catalogue.filter { !$0.isArchived }.map(\.id))
        var replacements = mostTrained.filter {
            !reserved.contains($0) && tileable.contains($0)
        }[...]
        return zip(kept, candidates).compactMap { keptLift, candidate in
            if let keptLift { return keptLift }
            return replacements.popFirst() ?? candidate
        }
    }
}
