/// One set the harness logs, as the scenario states it rather than as storage stores it.
struct DemonstrationSet {
    /// The load on the bar, in grams (`G-1.1`).
    let grams: Int

    /// Reps performed.
    let reps: Int

    /// The rated effort, or `nil` where none was recorded.
    let rpe: Double?

    /// Whether the set was a warmup — no personal record and no estimate come from one.
    let isWarmup: Bool

    /// Whether the set was completed. An abandoned set holds no record either (`G-1.8`).
    let isCompleted: Bool

    /// A working set, rated.
    static func working(_ grams: Int, reps: Int, rpe: Double) -> DemonstrationSet {
        DemonstrationSet(grams: grams, reps: reps, rpe: rpe, isWarmup: false, isCompleted: true)
    }

    /// A warmup. Logged because a real log contains them and the calculators have to exclude them.
    static func warmup(_ grams: Int, reps: Int) -> DemonstrationSet {
        DemonstrationSet(grams: grams, reps: reps, rpe: nil, isWarmup: true, isCompleted: true)
    }

    /// A working set that was started and not completed — the heaviest load in its session, so it
    /// would take every record if completion were ignored.
    static func abandoned(_ grams: Int, reps: Int) -> DemonstrationSet {
        DemonstrationSet(grams: grams, reps: reps, rpe: nil, isWarmup: false, isCompleted: false)
    }
}

/// One session's worth of it.
struct DemonstrationSession {
    /// How many days before the run's `now` the session happened.
    let daysAgo: Int

    /// Its sets, in the order they were performed.
    let sets: [DemonstrationSet]
}

/// The fixed history every run logs — two sessions, eight sets, one exercise.
///
/// The numbers are chosen so the printed answer is not the obvious one. Read against
/// `PersonalRecords.repRange`: the 3RM is held by 105 kg from the older session, which the newer
/// one never beat for three reps; the 4RM and 5RM are held by 102.5 kg; the 1RM and the best e1RM
/// are held by different sets in the same session, since 120 kg × 1 outranks 112.5 kg × 2 on load
/// while both estimate above every earlier set.
enum DemonstrationLog {
    /// The exercise the log is written against — a name the seeded catalogue ships (`TR-0.5.1`).
    static let exerciseName = "Back Squat"

    /// The two sessions, oldest first.
    static let sessions: [DemonstrationSession] = [
        DemonstrationSession(
            daysAgo: 7,
            sets: [
                .warmup(60_000, reps: 5),
                .working(100_000, reps: 5, rpe: 8),
                .working(105_000, reps: 3, rpe: 9),
                .abandoned(110_000, reps: 1),
            ]),
        DemonstrationSession(
            daysAgo: 0,
            sets: [
                .warmup(60_000, reps: 5),
                .working(102_500, reps: 5, rpe: 8.5),
                .working(112_500, reps: 2, rpe: 9),
                .working(120_000, reps: 1, rpe: 9.5),
            ]),
    ]
}
