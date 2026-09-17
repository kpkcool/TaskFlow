//
//  SyncEngine.swift
//  TaskFlow
//
//  Uploads pending local changes to Firestore and pulls remote changes back
//  into Core Data. Runs entirely off the main thread; UI observes `stateStream`.
//
//  Conflict resolution: "last updated wins" (see README).
//   - If a task is pending locally (create/update/delete not yet synced)
//     and also changed remotely, we compare `updatedAt`: local newer keeps
//     the local version and re-uploads it; remote newer overwrites Core
//     Data with the remote copy and marks it synced.
//   - A task that is `.synced` locally but is *missing* from the remote
//     collection is treated as a remote delete and removed locally too.
//
//  Retry: a failed create/update is marked `.failed` (still fully usable,
//  never lost) and retried with exponential backoff, on reconnect, on
//  app-foreground, and via manual "Sync Now". A failed delete stays
//  `.pendingDelete` (not `.failed`) purely so we never confuse "delete this"
//  with "create/update this" on the next attempt — see SyncOperation.
//
import Foundation
import os

actor SyncEngine {

    private let localStore: TaskLocalStoreProtocol
    private let remoteService: FirestoreTaskServiceProtocol
    private let queue = SyncQueue()

    private var isOnline = false
    private(set) var lastSyncDate: Date?

    private let stateContinuation: AsyncStream<SyncState>.Continuation
    nonisolated let stateStream: AsyncStream<SyncState>

    init(localStore: TaskLocalStoreProtocol, remoteService: FirestoreTaskServiceProtocol) {
        self.localStore = localStore
        self.remoteService = remoteService
        var continuation: AsyncStream<SyncState>.Continuation!
        self.stateStream = AsyncStream { continuation = $0 }
        self.stateContinuation = continuation
        stateContinuation.yield(.idle)
    }

    // MARK: - Triggers

    /// Call whenever NetworkMonitor reports a change.
    func updateConnectivity(_ online: Bool) async {
        let wasOffline = !isOnline
        isOnline = online
        if online {
            if wasOffline {
                AppLogger.sync.notice("Network restored — syncing pending changes.")
            }
            await syncNow()
        } else {
            stateContinuation.yield(.offline)
        }
    }

    /// Fire-and-forget nudge after a local mutation. Never awaited by
    /// callers — the UI already updated from Core Data before this runs.
    func notifyLocalChange() {
        guard isOnline else {
            stateContinuation.yield(.offline)
            return
        }
        _Concurrency.Task { await self.syncNow() }
    }

    /// Manual "Sync Now" / app-foreground / connectivity-restored entry
    /// point. Safe to call concurrently — only one pass runs at a time.
    func syncNow() async {
        guard isOnline else {
            stateContinuation.yield(.offline)
            return
        }
        guard await queue.beginIfIdle() else {
            return
        }

        do {
            let pending = try await localStore.fetchPendingSync()
            if !pending.isEmpty {
                stateContinuation.yield(.syncing(pendingCount: pending.count))
                for task in pending {
                    await process(task)
                }
            }
            await pullRemoteChanges()
            lastSyncDate = Date()
            stateContinuation.yield(.synced)
            
            /* TODO: PRAV REMOVE
             // Nothing to push and nothing to pull - skip the entire pass
             // so we don't flash "Syncing..." when there's no work to do.
             guard !pending.isEmpty else {
                 // Still try to pull remote changes (another device might
                 // have added tasks), but don't show "syncing" UI for it.
                 await pullRemoteChanges()
                 lastSyncDate = Date()

                 // Stay in the current state (don't flash synced→idle)
                 await queue.end()
                 return
             }

             stateContinuation.yield(.syncing(pendingCount: pending.count))
             for task in pending {
                 await process(task)
             }

             // Re-check: did all pending items succeed?
             let stillPending = try await localStore.fetchPendingSync()
             if stillPending.isEmpty {
                 await pullRemoteChanges()
                 lastSyncDate = Date()
                 stateContinuation.yield(.synced)
             } else {
                 // Some items failed - don't claim "synced", stay quiet.
                 // The retry timer (if under max attempts) will try again.
                 lastSyncDate = Date()
                 stateContinuation.yield(.idle)
             }
             */
            
        } catch {
            AppLogger.sync.error("Sync pass failed: \(error.localizedDescription, privacy: .public)")
            stateContinuation.yield(.failed(error.localizedDescription))
        }

        await queue.end()
    }

    // MARK: - Upload

    private func process(_ task: Task) async {
        guard let operation = SyncOperation.make(for: task) else { return }
        switch operation {
        case .create(let task), .update(let task):
            await attemptUpsert(task)
        case .delete(let task):
            await attemptDelete(task)
        }
    }

    private func attemptUpsert(_ task: Task) async {
        do {
            try await remoteService.updateTask(task)
            await queue.clearFailure(for: task.id)
            var synced = task
            synced.syncStatus = .synced
            try await localStore.upsert(synced)
        } catch {
            await handleFailure(for: task, error: error, fallbackStatus: .failed)
        }
    }

    private func attemptDelete(_ task: Task) async {
        do {
            try await remoteService.deleteTask(id: task.id)
            try await localStore.hardDelete(id: task.id)
            await queue.clearFailure(for: task.id)
        } catch {
            // Keep it `.pendingDelete` (not `.failed`) so the next pass
            // still knows to retry a delete, not a create/update.
            await handleFailure(for: task, error: error, fallbackStatus: .pendingDelete)
        }
    }

    private func handleFailure(for task: Task, error: Error, fallbackStatus: SyncStatus) async {
        let attempts = await queue.recordFailure(for: task.id)
        AppLogger.sync.error("Sync failed for task \(task.id.uuidString, privacy: .public) (attempt \(attempts)): \(error.localizedDescription, privacy: .public)")

        var updated = task
        updated.syncStatus = fallbackStatus
        try? await localStore.upsert(updated)

        guard attempts <= AppConstants.syncRetryMaxAttempts else {
            AppLogger.sync.error("Giving up automatic retries for task \(task.id.uuidString, privacy: .public); user can still tap Sync Now.")
            return
        }
        scheduleRetry(afterAttempts: attempts)
    }

    private func scheduleRetry(afterAttempts attempts: Int) {
        let backoff = AppConstants.syncRetryBaseDelaySeconds * UInt64(1 << min(attempts, 5))
        _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(nanoseconds: backoff * 1_000_000_000)
            await self?.syncNow()
        }
    }

    // MARK: - Download / merge

    private func pullRemoteChanges() async {
        do {
            let remoteTasks = try await remoteService.fetchTasks()
            let localTasks = try await localStore.fetchAllTasks()
            var remainingLocalIDs = Set(localTasks.map(\.id))
            let localByID = Dictionary(uniqueKeysWithValues: localTasks.map { ($0.id, $0) })

            for remote in remoteTasks {
                remainingLocalIDs.remove(remote.id)

                guard let local = localByID[remote.id] else {
                    // New from another client/device.
                    try await localStore.upsert(remote)
                    continue
                }

                if local.syncStatus.isPending {
                    // Last-updated-wins: only overwrite the pending local
                    // edit if the remote copy is strictly newer.
                    if remote.updatedAt > local.updatedAt {
                        try await localStore.upsert(remote)
                    }
                } else if remote.updatedAt > local.updatedAt {
                    try await localStore.upsert(remote)
                }
            }

            // Anything left over is local-only. If it's already `.synced`,
            // it must have been deleted remotely (by another client) —
            // remove it locally too. Pending items are left alone; they'll
            // be uploaded on the next pass.
            for id in remainingLocalIDs {
                guard let local = localByID[id], local.syncStatus == .synced else { continue }
                try await localStore.hardDelete(id: id)
            }
        } catch {
            AppLogger.sync.error("Pull failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
