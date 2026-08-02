/// A unit a `Weight` can be *displayed* in.
///
/// Storage is always `Int` grams (`G-1.1`); this type only ever affects presentation. Switching
/// the unit never mutates stored data (`G-3.2`) — it changes which `Weight` accessor a view calls,
/// nothing else. Which unit a user sees is a preference (`G-3.1`) and is not modelled here.
///
/// The raw values are the persisted spelling of that preference, so they are part of the storage
/// contract: renaming a case renames the stored string and orphans existing preferences.
public enum MassUnit: String, Sendable, Hashable, Codable, CaseIterable {
    /// Metric. 1 kg = 1000 g exactly, so kilogram display is lossless.
    case kilograms

    /// International avoirdupois pound. 1 lb = 453.59237 g exactly (by definition, since 1959),
    /// which is not a whole number of grams — so pound display is lossy by up to half a gram.
    case pounds
}

extension MassUnit {
    /// Grams in one unit. Both values are exact by definition, not measured approximations.
    ///
    /// Internal on purpose: the conversion belongs to `Weight`, and a public constant invites
    /// callers to do gram arithmetic in `Double` — which is the one thing `G-1.1` exists to stop.
    var gramsPerUnit: Double {
        switch self {
        case .kilograms: 1000
        case .pounds: 453.59237
        }
    }

    /// Grams in one thousandth of one unit — the resolution `Weight` formats at.
    ///
    /// For `.kilograms` this is exactly `1`, which is why kilogram display needs no conversion at
    /// all: one gram *is* one milli-kilogram.
    var gramsPerMilliUnit: Double {
        gramsPerUnit / 1000
    }
}
