//
//  SyncQueue.swift
//  TaskFlow
//
//  Tracks in-flight/retry bookkeeping for the SyncEngine: makes sure only
//  one sync pass runs at a time, and counts attempts per task for
//  exponential backoff.
//

import Foundation

actor SyncQueue {
    private var isSyncing = false
    private var retryCounts: [UUID: Int] = [:]

    /// Returns true (and reserves the slot) if no sync is currently running.
    func beginIfIdle() -> Bool {
        guard !isSyncing else { return false }
        isSyncing = true
        return true
    }

    func end() {
        isSyncing = false
    }

    func retryCount(for id: UUID) -> Int {
        retryCounts[id, default: 0]
    }

    @discardableResult
    func recordFailure(for id: UUID) -> Int {
        let next = retryCounts[id, default: 0] + 1
        retryCounts[id] = next
        return next
    }

    func clearFailure(for id: UUID) {
        retryCounts[id] = nil
    }
}
