//
//  TaskStatus.swift
//  TaskFlow
//
//  The three columns of the task board.
//

import Foundation

enum TaskStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case todo
    case inProgress
    case done

    var displayName: String {
        switch self {
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        }
    }
}
