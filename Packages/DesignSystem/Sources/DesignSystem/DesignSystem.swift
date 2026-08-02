// Design tokens, components and theme.
//
// Empty by design in Phase 0. G-7 (visual language) is a set of constraints on this package, not
// a Phase 0 deliverable — no Phase 0 requirement puts anything in it, and OUT-0.1 excludes every
// screen beyond a debug harness. The tokens arrive in Phase 1 under TR-1.4.
//
// Constraints for when it is filled in:
//
// - Dark-first theme, single orange brand accent (G-7.1, G-7.2).
// - Semantic colour is reserved: green for positive delta, red for failure. Never decorative
//   (G-7.3).
// - A defined type scale and spacing scale. No colour literals, font sizes or magic spacing
//   values in feature modules — enforced by the lint rules written in T-0.05 (G-7.7).
//
// This file exists because SwiftPM requires at least one source file per target.
