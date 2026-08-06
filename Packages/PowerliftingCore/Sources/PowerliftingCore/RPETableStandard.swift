extension RPETable {
    /// The conventional RPE/RIR chart, as an ``RPEBased`` formula reads it.
    ///
    /// **Provenance: transcribed from the RPE/RIR chart in wide circulation, and *not* verified
    /// against a primary publication.** The chart is generally attributed to Mike Tuchscherer
    /// (Reactive Training Systems) and appears in many secondary sources with the same values;
    /// no citation is given here because none has been checked. Treat these numbers as a working
    /// default, not as published reference values — `G-6.2` is **not** satisfied by them, and
    /// replacing this table with a sourced one is expected rather than hypothetical. `TR-0.5.2`
    /// makes that a content update rather than a code change.
    ///
    /// **The two rows most worth checking against a source are 10.5 and 11.** Every other step in
    /// the sequence eases smoothly, from −2.3 points near the top to −1.1 around 9.5; those two
    /// jump back to −1.6 before settling again. That is either a real feature of the chart or the
    /// place the transcription is wrong.
    ///
    /// ``repRange`` is 1 through 10, the extent of the chart's columns. It coincides with
    /// ``E1RMFormulaID/tabulatedRepRange`` and is not derived from it — the five closed-form
    /// equations arrive at the same bounds by a different argument entirely.
    public static let standard = RPETable(unchecked: standardEntries, repRange: 1...10)

    /// The rows of ``standard``, keyed by reps performed plus reps in reserve.
    ///
    /// Internal so a test can put them through ``init(entries:repRange:)``, which is what makes
    /// the unchecked construction above safe to trust: the validating path is never skipped, only
    /// moved into the suite.
    static let standardEntries: [Entry] = [
        Entry(repsToFailure: 1, fractionOfMax: 1.000),
        Entry(repsToFailure: 1.5, fractionOfMax: 0.978),
        Entry(repsToFailure: 2, fractionOfMax: 0.955),
        Entry(repsToFailure: 2.5, fractionOfMax: 0.939),
        Entry(repsToFailure: 3, fractionOfMax: 0.922),
        Entry(repsToFailure: 3.5, fractionOfMax: 0.907),
        Entry(repsToFailure: 4, fractionOfMax: 0.892),
        Entry(repsToFailure: 4.5, fractionOfMax: 0.878),
        Entry(repsToFailure: 5, fractionOfMax: 0.863),
        Entry(repsToFailure: 5.5, fractionOfMax: 0.850),
        Entry(repsToFailure: 6, fractionOfMax: 0.837),
        Entry(repsToFailure: 6.5, fractionOfMax: 0.824),
        Entry(repsToFailure: 7, fractionOfMax: 0.811),
        Entry(repsToFailure: 7.5, fractionOfMax: 0.799),
        Entry(repsToFailure: 8, fractionOfMax: 0.786),
        Entry(repsToFailure: 8.5, fractionOfMax: 0.774),
        Entry(repsToFailure: 9, fractionOfMax: 0.762),
        Entry(repsToFailure: 9.5, fractionOfMax: 0.751),
        Entry(repsToFailure: 10, fractionOfMax: 0.739),
        Entry(repsToFailure: 10.5, fractionOfMax: 0.723),
        Entry(repsToFailure: 11, fractionOfMax: 0.707),
        Entry(repsToFailure: 11.5, fractionOfMax: 0.694),
        Entry(repsToFailure: 12, fractionOfMax: 0.680),
        Entry(repsToFailure: 12.5, fractionOfMax: 0.667),
        Entry(repsToFailure: 13, fractionOfMax: 0.653),
        Entry(repsToFailure: 13.5, fractionOfMax: 0.638),
    ]

    /// Builds a table without checking it. Private to this file, whose only use is ``standard``.
    ///
    /// It exists because ``init(entries:repRange:)`` is failable and unwrapping it at a `static
    /// let` would need a force unwrap. The guarantee is not weakened, only relocated: a test runs
    /// ``standardEntries`` through the validating initialiser and fails if any guard would have
    /// rejected them.
    private init(unchecked entries: [Entry], repRange: ClosedRange<Int>) {
        self.entries = entries
        self.repRange = repRange
    }
}
