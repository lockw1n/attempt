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
