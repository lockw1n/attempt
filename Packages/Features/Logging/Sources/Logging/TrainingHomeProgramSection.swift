import DesignSystem
import Foundation
import RepositoryInterface
import SwiftUI

// FR-17.8.7: the Next-up card, its section and the accent rule that served them are gone from
// Train's root, which is the week now (`D-17.5`). What is left of `FR-16.8.2` on this side is
// `ProgramNextUpState`, which `T-17.13` reuses for **Start next week** — its reads of the run, the
// days and the routine names are the same reads that command needs, and rewriting them here would
// be that task's work done twice.
//
// The accent rule moved rather than being deleted: `StateActionEmphasis.weekCommand(on:among:)` in
// `WeekCardView.swift` is `trainCommand(under:)`'s successor, and it answers the same question over
// a different screen.
