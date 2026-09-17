//
//  SyncState.swift
//  TaskFlow
//
//  High-level sync status surfaced to the UI. Distinct from per-task
//  SyncStatus: this reflects the state of the SyncEngine as a whole.
//

import Foundation

enum SyncState: Equatable, Sendable {
    case idle
    case offline
    case syncing(pendingCount: Int)
    case synced
    case failed(String)

    var bannerMessage: String? {
        switch self {
        case .offline:
            return "You're offline. Changes will sync when you're back online."
        case .syncing(let pendingCount):
            return pendingCount > 0 ? "Syncing \(pendingCount) change\(pendingCount == 1 ? "" : "s")..." : "Syncing..."
        case .failed(let message):
            return "Sync failed: \(message)"
        case .synced, .idle:
            return nil
        }
    }
}
