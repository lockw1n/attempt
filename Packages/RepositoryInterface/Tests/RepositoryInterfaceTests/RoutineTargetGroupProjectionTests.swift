import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@Suite("RoutineTargetGroup → Prescription")
struct RoutineTargetGroupProjectionTests {
    // Non-throwing, and this is the whole of why: the one case this slice can store is the one case
    // it projects to, so there is nothing to refuse. See `RoutineTargetGroup.prescription`'s note.
    @Test("A target group's weight projects as a fixed-weight prescription")
    func projectsAsFixedWeight() {
        let group = codingRoutineTargetGroup()

        #expect(group.prescription == .fixedWeight(Weight(grams: 90_000)))
    }

    // FR-15.2.2. `nil` rather than a Prescription case, because the enum has none that means "no
    // load prescribed" — `.amrap` is a rep instruction that happens to carry none, and handing it
    // back here would turn an unfilled target into an instruction to work to failure.
    @Test("A blank target projects to no prescription at all")
    func blankProjectsToNothing() {
        let group = codingRoutineTargetGroup()
        let blank = RoutineTargetGroup(
            id: group.id,
            createdAt: group.createdAt,
            updatedAt: group.updatedAt,
            deletedAt: group.deletedAt,
            routineExerciseID: group.routineExerciseID,
            order: group.order,
            targetWeight: nil,
            targetReps: group.targetReps,
            targetSets: group.targetSets
        )

        #expect(blank.prescription == nil)
        #expect(blank.targetReps == group.targetReps, "a blank load leaves the reps prescribed")
        #expect(blank.targetSets == group.targetSets, "a blank load leaves the sets prescribed")
    }

    // The other side of the same line: zero is a load, and projects as one.
    @Test("A target weight of zero projects as a fixed weight of zero, not as blank")
    func zeroProjectsAsAWeight() {
        let group = codingRoutineTargetGroup()
        let zero = RoutineTargetGroup(
            id: group.id,
            createdAt: group.createdAt,
            updatedAt: group.updatedAt,
            deletedAt: group.deletedAt,
            routineExerciseID: group.routineExerciseID,
            order: group.order,
            targetWeight: Weight(grams: 0),
            targetReps: group.targetReps,
            targetSets: group.targetSets
        )

        #expect(zero.prescription == .fixedWeight(Weight(grams: 0)))
    }

    @Test("A negative target weight still projects, as assisted work")
    func negativeWeightProjects() {
        let group = codingRoutineTargetGroup()
        let assisted = RoutineTargetGroup(
            id: group.id,
            createdAt: group.createdAt,
            updatedAt: group.updatedAt,
            deletedAt: group.deletedAt,
            routineExerciseID: group.routineExerciseID,
            order: group.order,
            targetWeight: Weight(grams: -10_000),
            targetReps: group.targetReps,
            targetSets: group.targetSets
        )

        #expect(assisted.prescription == .fixedWeight(Weight(grams: -10_000)))
    }
}
