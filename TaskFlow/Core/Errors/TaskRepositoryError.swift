//
//  TaskRepositoryError.swift
//  TaskFlow
//

import Foundation

enum TaskRepositoryError: Error, LocalizedError, Equatable {
    case persistenceFailed(String)
    case networkUnavailable
    case syncFailed(String)
    case invalidTask(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .persistenceFailed(let reason):
            return "Couldn't save your changes locally: \(reason)"
        case .networkUnavailable:
            return "No network connection. Your change is saved and will sync later."
        case .syncFailed(let reason):
            return "Sync failed: \(reason)"
        case .invalidTask(let reason):
            return reason
        case .notFound:
            return "That task no longer exists."
        }
    }
}
