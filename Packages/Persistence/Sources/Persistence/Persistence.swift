// SwiftData models, schema versioning and repository implementations.
//
// Constraints on everything in this module:
//
// - The only target that may import SwiftData (TR-0.1.2).
// - Repositories expose domain value types and DTOs, never @Model instances (TR-0.4.3).
//   A @Model class escaping this package defeats the boundary.
// - CloudKit-compatible from schema v1 (G-2.5): every property optional or defaulted, no unique
//   constraints, every relationship optional. Compatible, not enabled — OUT-0.2.
// - Every entity carries id: UUID, createdAt, updatedAt (G-1.2) and soft-delete deletedAt
//   (G-1.3). Established in T-0.30 before any entity exists, because retrofitting them across
//   nine models is far more expensive.
// - The local store is the single source of truth (G-2.2). No repository method performs
//   network I/O.
//
// This file exists because SwiftPM requires at least one source file per target. Delete it once
// T-0.30 lands the entity conventions.
