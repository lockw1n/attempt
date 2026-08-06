// A minimal `Encoder`/`Decoder` pair for asserting `Codable` conformances without Foundation.
//
// Why this file exists (T-0.10). `Encodable` and `Decodable` are standard library, so conforming
// costs nothing — but `JSONEncoder` and `JSONDecoder` are Foundation, and `NFR-0.2` forbids
// Foundation in `PowerliftingCore`. The test target is held to the same rule: it runs on the
// Linux job (T-0.08) and a suite that drifts from its module's constraints stops being evidence
// about that module.
//
// The trap this avoids is that CI would not have caught it. T-0.08 proved the Linux job rejects
// `import SwiftUI` and `import CoreGraphics`, but Foundation ships on Linux via
// swift-corelibs-foundation, so a `JSONEncoder` round-trip would compile and go green on every
// job while quietly breaking the rule. Until T-0.05 adds a lint rule, this is enforced by
// choosing not to import it.
//
// What it covers. Single values — `Weight` is a bare integer of grams, `RoundingStrategy` a bare
// string, `DisplayPrecision` a bare integer — keyed objects since T-0.13 (`RoundingRule` was the
// module's first composite shape), and unkeyed arrays since T-0.12 (`SetRecord.modifiers` is the
// module's first collection). What remains trapped is an *explicitly requested* nested container:
// `nestedContainer(keyedBy:forKey:)` and friends on the encoding side. Nothing needs them —
// nesting happens by re-entering `ProbeEncoder`, which is how `Codable` synthesis and hand-written
// conformances both do it — and a type that reaches for a path the probe omits has changed its
// wire format, so that failure should be loud rather than silently accommodated.
//
// Key order is significant here. `ProbeValue.object` holds an *ordered* list of fields and
// compares in order, so an assertion against it pins key order as well as key spelling — which is
// what byte stability of a keyed shape means, and what T-0.20 has to assert per prescription case.
//
// Where the rest of it lives. This file holds the encoded-value vocabulary; the machinery is in
// `CodableProbeEncoding.swift` and `CodableProbeDecoding.swift`. It was one file until T-0.12,
// when the unkeyed containers took it past SwiftLint's 500-line ceiling — a real signal, not a
// nuisance, since T-0.20 is expected to grow it further still.

/// One encoded value — the entire vocabulary this module's wire formats use.
///
/// `object` keeps its fields in encoding order rather than in a dictionary, so equality is
/// order-sensitive. That is the point: reordering keys changes the bytes. `array` is ordered for
/// the same reason, and additionally because an array's order *is* its content.
enum ProbeValue: Equatable, Sendable, CustomStringConvertible {
    case null
    case bool(Bool)
    case string(String)
    case double(Double)
    case int(Int)
    case object([ProbeField])
    case array([ProbeValue])

    var description: String {
        switch self {
        case .null: "null"
        case .bool(let value): "bool(\(value))"
        case .string(let value): "string(\"\(value)\")"
        case .double(let value): "double(\(value))"
        case .int(let value): "int(\(value))"
        case .object(let fields): "object(\(fields.map(\.description).joined(separator: ", ")))"
        case .array(let elements): "array(\(elements.map(\.description).joined(separator: ", ")))"
        }
    }
}

/// One key–value pair of an encoded object, in the position it was written.
struct ProbeField: Equatable, Sendable, CustomStringConvertible {
    let key: String
    let value: ProbeValue

    var description: String { "\(key): \(value)" }
}

/// Raised when a probed type uses part of the `Codable` surface this probe deliberately omits.
struct ProbeUnsupported: Error, CustomStringConvertible {
    let what: String
    var description: String { "CodableProbe does not support \(what)" }
}
