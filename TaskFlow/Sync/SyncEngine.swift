//
//  SyncEngine.swift
//  TaskFlow
//
//  Uploads pending local changes to Firestore and pulls remote changes back
//  into Core Data. Runs entirely off the main thread; UI observes
//  `stateStream()` (a true multicast — see StateBroadcaster).
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
//  never lost). Retries happen on reconnect, on app-foreground, and via
//  manual "Sync Now" / pull-to-refresh. A failed delete stays
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

    /// Debounce token for coalescing rapid local mutations into one pass.
    private var pendingNudge: _Concurrency.Task<Void, Never>?

    /// Multicast so the board AND the debug screen can both observe without
    /// stealing each other's events. Replays the latest state on subscribe
    /// so a freshly-presented screen renders correctly immediately.
    private let stateBroadcaster = StateBroadcaster<SyncState>(initialValue: .idle)

    init(localStore: TaskLocalStoreProtocol, remoteService: FirestoreTaskServiceProtocol) {
        self.localStore = localStore
        self.remoteService = remoteService
    }

    /// Every caller gets an independent stream. Safe to call from anywhere.
    nonisolated func stateStream() -> AsyncStream<SyncState> {
        stateBroadcaster.stream()
    }

    nonisolated var currentState: SyncState {
        stateBroadcaster.value
    }

    // MARK: - Triggers

    /// Call whenever NetworkMonitor reports a change.
    func updateConnectivity(_ online: Bool) async {
        guard isOnline != online else { return }
        isOnline = online

        if online {
            AppLogger.sync.notice("Network available — checking for pending changes.")
            await syncNow()
        } else {
            AppLogger.sync.notice("Network unavailable — entering offline mode.")
            stateBroadcaster.send(.offline)
        }
    }

    /// Fire-and-forget nudge after a local mutation. Debounced: a burst of
    /// mutations (e.g. a drag firing moveTask + reorderTask, or a create
    /// firing createTask + moveTask) collapses into ONE sync pass rather
    /// than one pass per call.
    func notifyLocalChange() {
        guard isOnline else {
            stateBroadcaster.send(.offline)
            return
        }

        pendingNudge?.cancel()
        pendingNudge = _Concurrency.Task { [weak self] in
            // Short window is enough to absorb the multi-write sequences the
            // repository performs for one logical user action.
            try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
            guard !_Concurrency.Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Manual "Sync Now" / app-foreground / connectivity-restored entry
    /// point. Safe to call concurrently — only one pass runs at a time and
    /// overlapping requests collapse into a single follow-up pass.
    func syncNow() async {
        guard isOnline else {
            stateBroadcaster.send(.offline)
            return
        }
        guard await queue.beginIfIdle() else {
            // Another pass is running; it will do one follow-up for us.
            return
        }

        await runSyncPass()

        // If requests piled up during the pass, do exactly one more.
        if await queue.consumeFollowUpRequest() {
            await queue.end()
            await syncNow()
            return
        }

        await queue.end()
    }

    private func runSyncPass() async {
        do {
            // Deduplicate by task ID — the same task can legitimately appear
            // only once, but this guards against any store weirdness and
            // makes the "Syncing N changes" count match reality.
            let pending = try await uniquePendingTasks()

            guard !pending.isEmpty else {
                // Nothing to push. Quietly pull remote changes (another
                // device may have added something) without flashing
                // "Syncing..." at the user.
                await pullRemoteChanges()
                lastSyncDate = Date()
                if case .syncing = stateBroadcaster.value {
                    stateBroadcaster.send(.synced)
                }
                return
            }

            stateBroadcaster.send(.syncing(pendingCount: pending.count))

            for task in pending {
                // Skip if another overlapping pass already claimed this ID.
                guard await queue.beginProcessing(task.id) else { continue }
                await process(task)
                await queue.endProcessing(task.id)
            }

            let stillPending = try await uniquePendingTasks()
            lastSyncDate = Date()

            if stillPending.isEmpty {
                await pullRemoteChanges()
                stateBroadcaster.send(.synced)
            } else {
                // Some uploads failed. Report it plainly instead of leaving
                // the UI stuck on "Syncing N changes..." forever.
                let message = "\(stillPending.count) change\(stillPending.count == 1 ? "" : "s") couldn't sync"
                AppLogger.sync.error("\(message, privacy: .public)")
                stateBroadcaster.send(.failed(message))
            }
        } catch {
            AppLogger.sync.error("Sync pass failed: \(error.localizedDescription, privacy: .public)")
            stateBroadcaster.send(.failed(error.localizedDescription))
        }
    }

    /// Pending tasks, deduplicated by ID (keeping the newest `updatedAt`).
    private func uniquePendingTasks() async throws -> [Task] {
        let pending = try await localStore.fetchPendingSync()
        var byID: [UUID: Task] = [:]
        for task in pending {
            if let existing = byID[task.id], existing.updatedAt >= task.updatedAt { continue }
            byID[task.id] = task
        }
        return byID.values.sorted { $0.updatedAt < $1.updatedAt }
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

            // Re-read before marking synced: the user may have edited this
            // task again while the upload was in flight. Overwriting with
            // our stale copy would silently lose that edit.
            guard let latest = try? await localStore.fetchTask(id: task.id) else { return }
            guard latest.updatedAt <= task.updatedAt else {
                AppLogger.sync.notice("Task \(task.id.uuidString, privacy: .public) changed mid-upload; leaving pending for next pass.")
                return
            }

            var synced = latest
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

        // Only rewrite Core Data if the status actually changes — otherwise
        // we trigger a needless store write → observeTasks emission → UI
        // reload on every single failed attempt.
        guard let latest = try? await localStore.fetchTask(id: task.id) else { return }
        guard latest.syncStatus != fallbackStatus else { return }

        var updated = latest
        updated.syncStatus = fallbackStatus
        try? await localStore.upsert(updated)

        // No automatic retry timer — that produced an infinite loop that
        // kept flashing "Syncing 1 change...". Retries happen via:
        //   • Network connectivity restored
        //   • App becomes active (foreground)
        //   • Pull-to-refresh / tapping the sync icon
        //   • "Sync Now" in the Debug screen
        if attempts >= AppConstants.syncRetryMaxAttempts {
            AppLogger.sync.error("Giving up automatic retries for task \(task.id.uuidString, privacy: .public); user can still tap Sync Now.")
        }
    }

    // MARK: - Download / merge

    private func pullRemoteChanges() async {
        do {
            let remoteTasks = try await remoteService.fetchTasks()
            let localTasks = try await localStore.fetchAllTasks()
            var remainingLocalIDs = Set(localTasks.map(\.id))
            var localByID: [UUID: Task] = [:]
            for task in localTasks { localByID[task.id] = task }

            for remote in remoteTasks {
                remainingLocalIDs.remove(remote.id)

                guard let local = localByID[remote.id] else {
                    // New from another client/device.
                    try await localStore.upsert(remote)
                    continue
                }

                // Last-updated-wins, but only when the remote copy is
                // MEANINGFULLY newer (see `isMeaningfullyNewer`). Comparing
                // raw `>` caused an endless write loop: a task we just
                // uploaded comes back from Firestore with a sub-millisecond
                // different timestamp (Timestamp <-> Date isn't bit-exact),
                // looking "newer", so we'd rewrite Core Data → emit a new
                // snapshot → churn the UI, forever.
                guard Self.isMeaningfullyNewer(remote.updatedAt, than: local.updatedAt) else { continue }

                // Don't clobber a local edit that hasn't been uploaded yet
                // unless the remote really is newer (checked above).
                try await localStore.upsert(remote)
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

    /// Firestore's `Timestamp` and Foundation's `Date` don't round-trip
    /// bit-exactly, so a freshly-uploaded task reads back with a timestamp
    /// that differs by fractions of a millisecond. Require a real gap before
    /// treating the remote copy as newer.
    private static func isMeaningfullyNewer(_ remote: Date, than local: Date) -> Bool {
        remote.timeIntervalSince(local) > AppConstants.syncTimestampToleranceSeconds
    }
}
