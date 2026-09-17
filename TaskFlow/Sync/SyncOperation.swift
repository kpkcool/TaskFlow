//
//  SyncOperation.swift
//  TaskFlow
//
//  What the SyncEngine intends to do with a given pending task. Derived
//  from Task.syncStatus at the moment sync runs.
//

import Foundation

enum SyncOperation: Sendable {
    case create(Task)
    case update(Task)
    case delete(Task)

    var task: Task {
        switch self {
        case .create(let task), .update(let task), .delete(let task):
            return task
        }
    }

    /// Maps a locally-pending task to the operation the engine should
    /// attempt. `nil` for tasks that don't need any network work.
    static func make(for task: Task) -> SyncOperation? {
        switch task.syncStatus {
        case .pendingCreate, .failed:
            return .create(task)
        case .pendingUpdate:
            return .update(task)
        case .pendingDelete:
            return .delete(task)
        case .synced:
            return nil
        }
    }
}
