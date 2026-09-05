import Foundation
import Persistence
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

// The shared conformance suite's scaffolding: what a subject is, and the records every test builds
// from.
//
// ONE SUITE, TWO SUBJECTS, AND EVERY TEST RUNS TWICE. `@Test(arguments: Subject.all)` is the whole
// mechanism — there is no base class to subclass and no protocol for a test author to forget to
// conform to, so a test added here is a test both implementations must pass, by construction. A
// suite that had to be re-listed per subject is a suite that drifts one subject at a time, which is
// the failure this task exists to prevent.
//
// WHAT THE SUITE MAY DO TO A SUBJECT IS EXACTLY WHAT THE PROTOCOLS OFFER, and that boundary is
// the settled answer to "how does a shared suite seed a row no repository will write". It does not,
// and the three cases that prompted the question turn out to be three different answers:
//
//   A LIVE SET UNDER A DELETED ENTRY needs no seeding at all. Saving a set whose entry is
//   soft-deleted is legal — a soft-deleted target is not a dangling reference — so the state is
//   built through the front door, by both subjects, and `theCascadeReachesThroughADeletedEntry`
//   does exactly that.
//
//   A DUPLICATE `id` cannot be reached: every save upserts by id and `settings()` is find-or-create.
//   A seeding door for it would have to be matched by an OBSERVATION door — no protocol read
//   returns both rows — and both doors would be a second, untested contract shaped by whichever
//   subject implemented it first. It would also force the fakes to store arrays and carry their own
//   copy of the tiebreak, so the suite would be asserting a rule the fake exists in order not to
//   have. `G-2.4`'s tiebreak stays `Persistence`'s, tested there.
//
//   AN UNMAPPABLE VOCABULARY SPELLING is not representable in a record at all: `Exercise.laterality`
//   is a `Laterality`, and rule 4 resolves the stored string to a fallback before any record exists.
//   There is no record-shaped door that could express it. It is a mapping behaviour rather than a
//   repository one, and `RecordMappingTests` is where it lives.
//
// FOUR THINGS ARE THEREFORE OUT OF SCOPE HERE, each named so the exclusion is a decision rather than
// an omission, and each still tested on the side that can reach it:
//
//   1. the duplicate-`id` tiebreak, and its residual, which T-0.42 deliberately left open;
//   2. a save writing every duplicate rather than the tiebreak winner;
//   3. `settings()` finding a soft-deleted settings row (this protocol has no delete);
//   4. a soft-deleted exercise or training-max row being hidden by default — no protocol call
//      deletes either, so only the `includingDeleted:` flag's *live* half is reachable, and that
//      half is asserted.
//
// Every other behaviour of every method on every protocol is here.
// `PersonalRecordCacheRepository` (TR-1.6) joined a phase after the rest and brought two of those
// three: its reconciliation is cross-row and is written twice, once per subject, which is exactly
// the drift this suite exists to catch. `RoutineRepository` (FR-15.2) joined later still, with the
// same shape of hand-written-twice cascade.
//
// **THE METHOD COUNT USED TO BE SPELLED OUT HERE AND IT WAS WRONG.** This line read "all
// thirty-one methods" while the protocols carried thirty-three — the cache repository had grown
// from one method to three and the prose did not move — and it then survived a whole new protocol
// being added beside it. A total in a comment is a claim about a set that nothing walks, so it is
// stale from the first member added after it is written, and it reads as authoritative the whole
// time. What holds the claim now is the tests below naming their own populations ("on all eight
// deletes") plus `Repositories` failing to compile when a protocol is added and not threaded
// through both subjects.

/// One implementation of the protocols, as the suite sees it.
struct Subject: Sendable, CustomTestStringConvertible {
    let name: String
    private let build: @Sendable () throws -> Repositories

    /// A fresh, empty instance. Called once per test — the two subjects are independent stores.
    func make() throws -> Repositories { try build() }

    var testDescription: String { name }

    /// The SwiftData implementations over an in-memory store, and the fakes.
    ///
    /// `PersistenceStack(location: .inMemory)` is the supported way to build a container from
    /// outside the module: it takes the lock that serialises `ModelContainer` construction, which a
    /// suite running its cases in parallel very much needs.
    static let all: [Subject] = [
        Subject(name: "PersistenceStack") {
            let stack = try PersistenceStack(location: .inMemory)
            return Repositories(
                exercises: stack.exercises,
                trainingMaxes: stack.trainingMaxes,
                workouts: stack.workouts,
                settings: stack.settings,
                bodyweight: stack.bodyweight,
                equipment: stack.equipment,
                personalRecords: stack.personalRecords,
                routines: stack.routines,
                programs: stack.programs,
                plannedTargets: stack.workouts
            )
        },
        Subject(name: "InMemoryRepositoryStack") {
            let stack = InMemoryRepositoryStack()
            return Repositories(
                exercises: stack.exercises,
                trainingMaxes: stack.trainingMaxes,
                workouts: stack.workouts,
                settings: stack.settings,
                bodyweight: stack.bodyweight,
                equipment: stack.equipment,
                personalRecords: stack.personalRecords,
                routines: stack.routines,
                programs: stack.programs,
                plannedTargets: stack.workouts
            )
        },
    ]
}

/// The existentials, in the shape both stacks hand out.
struct Repositories: Sendable {
    let exercises: any ExerciseRepository
    let trainingMaxes: any TrainingMaxRepository
    let workouts: any WorkoutRepository
    let settings: any SettingsRepository
    let bodyweight: any BodyweightRepository
    let equipment: any EquipmentRepository
    let personalRecords: any PersonalRecordCacheRepository
    let routines: any RoutineRepository
    let programs: any ProgramRepository
    let plannedTargets: any PlannedTargetRepository
}
