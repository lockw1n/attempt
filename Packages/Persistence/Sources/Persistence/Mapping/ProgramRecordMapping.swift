import Foundation
import RepositoryInterface
import SwiftData

// The three program entities. See `RecordMapping.swift` for the three members' contract and for why
// `update(from:)` leaves the audit columns alone.

extension ProgramEntity: RecordMappable {
    /// This row as a record.
    var record: Program {
        Program(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            name: name,
            notes: notes
        )
    }

    /// A new row carrying `record`.
    convenience init(record: Program) {
        self.init(
            id: record.id,
            name: record.name,
            notes: record.notes,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    /// Overwrites this row from `record`.
    func update(from record: Program) {
        name = record.name
        notes = record.notes
    }
}

extension ProgramDayEntity: RecordMappable {
    /// This row as a record.
    var record: ProgramDay {
        ProgramDay(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            programID: programID,
            routineID: routineID,
            order: order
        )
    }

    /// A new row carrying `record`.
    convenience init(record: ProgramDay) {
        self.init(
            id: record.id,
            programID: record.programID,
            routineID: record.routineID,
            order: record.order,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    /// Overwrites this row from `record`.
    func update(from record: ProgramDay) {
        programID = record.programID
        routineID = record.routineID
        order = record.order
    }
}

extension ProgramRunEntity: RecordMappable {
    /// This row as a record.
    var record: ProgramRun {
        ProgramRun(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            programID: programID,
            startedAt: startedAt,
            endedAt: endedAt,
            weekNumber: weekNumber,
            nextDayIndex: nextDayIndex
        )
    }

    /// A new row carrying `record`.
    convenience init(record: ProgramRun) {
        self.init(
            id: record.id,
            programID: record.programID,
            startedAt: record.startedAt,
            weekNumber: record.weekNumber,
            nextDayIndex: record.nextDayIndex,
            endedAt: record.endedAt,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    /// Overwrites this row from `record`.
    func update(from record: ProgramRun) {
        programID = record.programID
        startedAt = record.startedAt
        endedAt = record.endedAt
        weekNumber = record.weekNumber
        nextDayIndex = record.nextDayIndex
    }
}
