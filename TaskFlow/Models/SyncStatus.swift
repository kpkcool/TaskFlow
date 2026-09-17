//
//  SyncStatus.swift
//  TaskFlow
//
//  Tracks whether a task's local state has been reflected in Firestore.
//

import Foundation

enum SyncStatus: String, Codable, Hashable, Sendable {
    case synced
    case pendingCreate
    case pendingUpdate
    case pendingDelete
    case failed

    /// Whether this task still has work the SyncEngine needs to do.
    var isPending: Bool {
        switch self {
        case .synced:
            return false
        case .pendingCreate, .pendingUpdate, .pendingDelete, .failed:
            return true
        }
    }

    /// SF Symbol name for the status badge. Deliberately not a raw emoji
    /// character in a UILabel — glyphs like "⏳" depend on the emoji font
    /// being available and can silently fall back to a "missing glyph" box
    /// on some simulators/devices. An SF Symbol in a UIImageView always
    /// renders as a crisp, reliably-tintable template image instead.
    var symbolName: String {
        switch self {
        case .synced: return "checkmark.circle.fill"
        case .pendingCreate, .pendingUpdate, .pendingDelete: return "clock.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}
