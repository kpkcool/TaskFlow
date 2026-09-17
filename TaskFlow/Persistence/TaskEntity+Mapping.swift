//
//  TaskEntity+Mapping.swift
//  TaskFlow
//
//  Converts between the Core Data row and the plain-value domain model.
//  This is the only place that needs to know both types exist.
//

import CoreData
import Foundation

extension TaskEntity {

    func toDomain() -> Task {
        Task(
            id: id,
            title: title,
            taskDescription: taskDescription,
            status: TaskStatus(rawValue: status) ?? .todo,
            createdAt: createdAt,
            updatedAt: updatedAt,
            sortOrder: sortOrder,
            syncStatus: SyncStatus(rawValue: syncStatus) ?? .pendingCreate
        )
    }

    func update(from task: Task) {
        id = task.id
        title = task.title
        taskDescription = task.taskDescription
        status = task.status.rawValue
        createdAt = task.createdAt
        updatedAt = task.updatedAt
        sortOrder = task.sortOrder
        syncStatus = task.syncStatus.rawValue
        isDeletedPendingSync = (task.syncStatus == .pendingDelete)
    }
}
