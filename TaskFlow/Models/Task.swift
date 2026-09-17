//
//  Task.swift
//  TaskFlow
//
//  Domain model used everywhere above the persistence layer.
//  This is a plain value type: Core Data and Firestore details never leak
//  past the Repository boundary.
//

import Foundation

struct Task: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var taskDescription: String
    var status: TaskStatus
    let createdAt: Date
    var updatedAt: Date
    var sortOrder: Double
    var syncStatus: SyncStatus

    init(
        id: UUID = UUID(),
        title: String,
        taskDescription: String,
        status: TaskStatus,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Double,
        syncStatus: SyncStatus
    ) {
        self.id = id
        self.title = title
        self.taskDescription = taskDescription
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.syncStatus = syncStatus
    }
}

/// A single column of the board, sorted by `sortOrder`.
struct TaskSection: Identifiable, Equatable, Sendable {
    let status: TaskStatus
    var tasks: [Task]

    var id: TaskStatus { status }
}
