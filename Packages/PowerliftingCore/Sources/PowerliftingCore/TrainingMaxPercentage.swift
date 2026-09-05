extension Weight {
    /// This load read as a percentage of a training max, to the nearest whole percent
    /// (`FR-16.7.1`).
    ///
    /// **Whole percents, halves away from zero.** The annotation sits beside a load that is already
    /// rendered at `G-3.3`'s step, and a second decimal there would be precision the number it
    /// annotates does not have. `87.5` becomes `88`, `-87.5` becomes `-88`.
    ///
    /// **Integer arithmetic rather than ``scaled(by:)``'s crossing.** That function goes out to
    /// `Double` and back because it produces a *weight*; this produces a percent, so there is
    /// nothing to round to whole grams and no reason to leave `Int`.
    ///
    /// **`nil` is a real answer and the screen draws nothing for it** — no zero and no dash. A
    /// training max of zero divides by nothing, and a negative one would report an ordinary load as
    /// a negative share of it, which is `TrainingMaxUnresolvedReason.negativeSourceWeight`'s
    /// refusal one layer out. Overflow answers `nil` for the same reason: an absent annotation is
    /// the honest rendering of a number this build cannot produce.
    ///
    /// The load itself may be negative — assisted work is signed on purpose — and reads as a
    /// negative percentage of a positive training max.
    ///
    /// - Parameter trainingMax: The number in force on the session's training day.
    /// - Returns: The percentage, or `nil` where there is none to state.
    public func percentOfTrainingMax(_ trainingMax: Weight) -> Int? {
        guard trainingMax.grams > 0 else { return nil }
        let (scaled, overflowed) = grams.multipliedReportingOverflow(by: 100)
        guard !overflowed else { return nil }
        let whole = scaled / trainingMax.grams
        let remainder = scaled % trainingMax.grams
        // `remainder` carries the dividend's sign, so the half-way step is taken in the direction
        // the quotient already points — which is what makes this away-from-zero rather than
        // upwards, and keeps `-87.5%` and `87.5%` symmetric.
        guard 2 * abs(remainder) >= trainingMax.grams else { return whole }
        return remainder < 0 ? whole - 1 : whole + 1
    }
}
