//
//  TaskRepositoryImpl.swift
//  TaskFlow
//
//  Implements the offline-first write strategy required everywhere in this
//  app: save to Core Data first, return to the caller immediately, and only
//  then (fire-and-forget) nudge the SyncEngine to push to Firestore if we
//  think we're online. The UI never waits on a network call.
//
import Foundation

final class TaskRepositoryImpl: TaskRepository, @unchecked Sendable {

    private let localStore: TaskLocalStoreProtocol
    private let syncEngine: SyncEngine

    init(
        localStore: TaskLocalStoreProtocol,
        syncEngine: SyncEngine
    ) {
        self.localStore = localStore
        self.syncEngine = syncEngine
    }

    // MARK: - Observation

    func observeTasks() -> AsyncStream<[Task]> {
        let upstream = localStore.observeTasks()
        return AsyncStream { continuation in
            let forwarding = _Concurrency.Task {
                for await tasks in upstream {
                    // Soft-deleted tasks stay in Core Data until their
                    // delete is confirmed synced; the UI should never see them.
                    let visible = tasks.filter { $0.syncStatus != .pendingDelete }
                    continuation.yield(visible)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in forwarding.cancel() }
        }
    }

    func observeSyncState() -> AsyncStream<SyncState> {
        syncEngine.stateStream
    }

    func pendingChangeCount() async -> Int {
        (try? await localStore.fetchPendingSync())?.count ?? 0
    }

    func lastSyncDate() async -> Date? {
        await syncEngine.lastSyncDate
    }

    func clearAllLocalData() async throws {
        try await localStore.hardDeleteAll()
    }

    // MARK: - Mutations

    func createTask(title: String, description: String) async throws -> Task {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw TaskRepositoryError.invalidTask("Title cannot be empty")
        }

        let existing = try await localStore.fetchAllTasks()
        let lastInColumn = existing
            .filter { $0.status == .todo && $0.syncStatus != .pendingDelete }
            .map(\.sortOrder)
            .max()

        let now = Date()
        let task = Task(
            title: trimmedTitle,
            taskDescription: description,
            status: .todo,
            createdAt: now,
            updatedAt: now,
            sortOrder: SortOrderCalculator.appending(after: lastInColumn),
            syncStatus: .pendingCreate
        )

        try await localStore.upsert(task)
        await syncEngine.notifyLocalChange()
        return task
    }

    func updateTask(_ task: Task) async throws {
        let trimmedTitle = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw TaskRepositoryError.invalidTask("Title cannot be empty")
        }
        guard let existing = try await localStore.fetchTask(id: task.id) else {
            throw TaskRepositoryError.notFound
        }

        var updated = task
        updated.title = trimmedTitle
        updated.updatedAt = Date()
        updated.syncStatus = Self.pendingStatusAfterEdit(existing)

        try await localStore.upsert(updated)
        await syncEngine.notifyLocalChange()
    }

    func deleteTask(_ task: Task) async throws {
        guard let existing = try await localStore.fetchTask(id: task.id) else { return }

        if existing.syncStatus == .pendingCreate {
            // Never made it to Firestore in the first place — nothing to
            // sync, so it's safe to remove the local row outright.
            try await localStore.hardDelete(id: task.id)
            return
        }

        var pendingDelete = existing
        pendingDelete.updatedAt = Date()
        pendingDelete.syncStatus = .pendingDelete
        try await localStore.upsert(pendingDelete)
        await syncEngine.notifyLocalChange()
    }

    func moveTask(_ task: Task, to status: TaskStatus) async throws {
        guard var existing = try await localStore.fetchTask(id: task.id) else {
            throw TaskRepositoryError.notFound
        }

        let siblings = try await localStore.fetchAllTasks()
        let lastInTarget = siblings
            .filter { $0.id != task.id && $0.status == status && $0.syncStatus != .pendingDelete }
            .map(\.sortOrder)
            .max()

        let newStatus = Self.pendingStatusAfterEdit(existing)
        existing.status = status
        existing.sortOrder = SortOrderCalculator.appending(after: lastInTarget)
        existing.updatedAt = Date()
        existing.syncStatus = newStatus

        try await localStore.upsert(existing)
        await syncEngine.notifyLocalChange()
    }

    func reorderTask(_ task: Task, newSortOrder: Double) async throws {
        guard var existing = try await localStore.fetchTask(id: task.id) else {
            throw TaskRepositoryError.notFound
        }

        let newStatus = Self.pendingStatusAfterEdit(existing)
        existing.sortOrder = newSortOrder
        existing.updatedAt = Date()
        existing.syncStatus = newStatus

        try await localStore.upsert(existing)
        await syncEngine.notifyLocalChange()
    }

    func syncPendingChanges() async {
        await syncEngine.syncNow()
    }

    // MARK: - Helpers

    /// A task still waiting on its very first upload stays `.pendingCreate`
    /// after further local edits (there's nothing to "update" remotely
    /// yet); anything already known to Firestore becomes `.pendingUpdate`.
    private static func pendingStatusAfterEdit(_ existing: Task) -> SyncStatus {
        existing.syncStatus == .pendingCreate ? .pendingCreate : .pendingUpdate
    }
}
