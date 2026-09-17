//
//  MockTaskStore.swift
//  TaskFlowTests
//
//  In-memory stand-in for CoreDataTaskStore so Repository/SyncEngine tests
//  never touch a real persistent store.
//

import Foundation
@testable import TaskFlow

final class MockTaskStore: TaskLocalStoreProtocol, @unchecked Sendable {

    private let lock = NSLock()
    private var tasks: [UUID: Task] = [:]
    private var continuations: [UUID: AsyncStream<[Task]>.Continuation] = [:]

    init(initialTasks: [Task] = []) {
        for task in initialTasks {
            tasks[task.id] = task
        }
    }

    func observeTasks() -> AsyncStream<[Task]> {
        AsyncStream { [weak self] continuation in
            guard let self else { return }
            let id = UUID()
            let current: [Task] = self.lock.withLock {
                self.continuations[id] = continuation
                return self.sortedTasks()
            }
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?.continuations[id] = nil }
            }
        }
    }

    func fetchAllTasks() async throws -> [Task] {
        lock.withLock { sortedTasks() }
    }

    func fetchTask(id: UUID) async throws -> Task? {
        lock.withLock { tasks[id] }
    }

    func upsert(_ task: Task) async throws {
        let subscribers: [UUID: AsyncStream<[Task]>.Continuation]
        let snapshot: [Task]
        (subscribers, snapshot) = lock.withLock {
            tasks[task.id] = task
            return (continuations, sortedTasks())
        }
        for (_, continuation) in subscribers { continuation.yield(snapshot) }
    }

    func upsertAll(_ tasksToUpsert: [Task]) async throws {
        let subscribers: [UUID: AsyncStream<[Task]>.Continuation]
        let snapshot: [Task]
        (subscribers, snapshot) = lock.withLock {
            for task in tasksToUpsert { tasks[task.id] = task }
            return (continuations, sortedTasks())
        }
        for (_, continuation) in subscribers { continuation.yield(snapshot) }
    }

    func hardDelete(id: UUID) async throws {
        let subscribers: [UUID: AsyncStream<[Task]>.Continuation]
        let snapshot: [Task]
        (subscribers, snapshot) = lock.withLock {
            tasks[id] = nil
            return (continuations, sortedTasks())
        }
        for (_, continuation) in subscribers { continuation.yield(snapshot) }
    }

    func hardDeleteAll() async throws {
        let subscribers: [UUID: AsyncStream<[Task]>.Continuation]
        (subscribers, _) = lock.withLock {
            tasks.removeAll()
            return (continuations, sortedTasks())
        }
        for (_, continuation) in subscribers { continuation.yield([]) }
    }

    func fetchPendingSync() async throws -> [Task] {
        lock.withLock {
            tasks.values
                .filter { $0.syncStatus != .synced }
                .sorted { $0.updatedAt < $1.updatedAt }
        }
    }

    /// Test-only synchronous peek, bypassing the async API.
    func snapshot() -> [Task] {
        lock.withLock { sortedTasks() }
    }

    private func sortedTasks() -> [Task] {
        tasks.values.sorted { $0.sortOrder < $1.sortOrder }
    }
}
