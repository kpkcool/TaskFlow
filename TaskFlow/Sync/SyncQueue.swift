//
//  SyncQueue.swift
//  TaskFlow
//
//  Tracks in-flight/retry bookkeeping for the SyncEngine: makes sure only
//  one sync pass runs at a time, coalesces requests that arrive while a
//  pass is already running, and counts per-task failures.
//

import Foundation

actor SyncQueue {
    private var isSyncing = false
    private var retryCounts: [UUID: Int] = [:]

    /// Set when a sync is requested while one is already in flight. The
    /// running pass checks this on completion and does exactly ONE
    /// follow-up pass, instead of every caller queuing its own.
    ///
    /// This is what stops a single drag (which fires moveTask + reorderTask)
    /// or a create-with-status (createTask + moveTask) from kicking off
    /// several redundant full sync passes back to back.
    private var followUpRequested = false

    /// Task IDs currently being uploaded. Prevents the same task being
    /// processed twice concurrently if passes overlap.
    private var inFlightIDs: Set<UUID> = []

    /// Returns true (and reserves the slot) if no sync is currently running.
    /// If a sync IS running, records that another pass is wanted and
    /// returns false.
    func beginIfIdle() -> Bool {
        guard !isSyncing else {
            followUpRequested = true
            return false
        }
        isSyncing = true
        followUpRequested = false
        return true
    }

    func end() {
        isSyncing = false
        inFlightIDs.removeAll()
    }

    /// True if at least one sync request arrived while the last pass was
    /// running. Consumes the flag.
    func consumeFollowUpRequest() -> Bool {
        defer { followUpRequested = false }
        return followUpRequested
    }

    // MARK: - Per-task in-flight tracking

    /// Reserves `id` for upload. Returns false if it's already in flight.
    func beginProcessing(_ id: UUID) -> Bool {
        guard !inFlightIDs.contains(id) else { return false }
        inFlightIDs.insert(id)
        return true
    }

    func endProcessing(_ id: UUID) {
        inFlightIDs.remove(id)
    }

    // MARK: - Failure counts

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
