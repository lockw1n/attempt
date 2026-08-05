/// What an exercise is performed with.
///
/// Filtered on in the exercise library (`FR-1.1.2`) and chosen when creating a custom exercise
/// (`FR-1.1.3`); stored on `ExerciseEntity` (`TR-0.3.1`) and required on every catalogue entry
/// (`TR-0.5.1`).
///
/// **The case list is the deliverable, not the code.** The seed catalogue is authored against
/// these spellings and validated on import, so a case missing by then means re-authoring the
/// catalogue rather than adding an enum case. That is why the list is broader than the app needs
/// today.
///
/// **This answers "what kind of implement", not "which bar".** Which bar is ``BarType``; how much
/// it weighs is neither, and belongs to the equipment profile (`FR-1.4.2`, `TR-0.3.7`). A
/// safety-squat-bar squat is `.barbell` + ``BarType/safetySquat``.
///
/// Unknown values decode to ``other``.
public enum Equipment: String, Sendable, Hashable, Codable, CaseIterable {
    /// A loadable bar. The competition lifts and most of their variations.
    case barbell

    /// One or two dumbbells.
    case dumbbell

    /// One or two kettlebells. Separate from ``dumbbell`` because the two are not interchangeable
    /// for the exercises that name them (swings, Turkish get-ups).
    case kettlebell

    /// A fixed-path resistance machine — leg press, hack squat, pec deck, plate- or pin-loaded.
    case machine

    /// A cable stack or pulley. Distinct from ``machine`` because the resistance profile and the
    /// available exercises differ, and lifters filter for one or the other.
    case cable

    /// A Smith machine. Its own case rather than a ``machine`` or a ``barbell``: the bar is guided,
    /// its own mass is gym-specific and often not 20 kg, and treating a Smith squat as a barbell
    /// squat would silently pollute an exercise's history and PRs.
    case smithMachine

    /// Load is the lifter's own bodyweight — pull-ups, dips, push-ups. Added external load is
    /// recorded on the set, not here.
    case bodyweight

    /// Elastic resistance. Its own case because band tension is not a `Weight` and never
    /// participates in plate maths (`TR-0.2.7`).
    case band

    /// Anything the cases above do not describe — sleds, ab wheels, specialty rigs — and the
    /// landing place for an equipment value from a newer app version.
    case other
}

extension Equipment {
    /// Decodes equipment, degrading an unrecognised spelling to ``other`` instead of throwing —
    /// same policy as ``Movement/init(from:)``, since equipment is an equally open-ended
    /// vocabulary. A non-string value still throws.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = Equipment(rawValue: raw) ?? .other
    }
}
