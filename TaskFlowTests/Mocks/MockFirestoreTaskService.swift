//
//  MockFirestoreTaskService.swift
//  TaskFlowTests
//
//  Stands in for the real Firestore SDK so sync tests never hit the
//  network. `shouldFail` lets tests simulate a Firebase outage.
//

import Foundation
@testable import TaskFlow

final class MockFirestoreTaskService: FirestoreTaskServiceProtocol, @unchecked Sendable {

    private let lock = NSLock()
    private var remoteTasks: [UUID: Task] = [:]

    var shouldFail = false
    var failError: Error = TaskRepositoryError.syncFailed("mock failure")

    private(set) var createCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var deleteCallCount = 0
    private(set) var fetchCallCount = 0

    init(initialTasks: [Task] = []) {
        for task in initialTasks {
            remoteTasks[task.id] = task
        }
    }

    func fetchTasks() async throws -> [Task] {
        fetchCallCount += 1
        if shouldFail { throw failError }
        return lock.withLock { Array(remoteTasks.values) }
    }

    func createTask(_ task: Task) async throws {
        createCallCount += 1
        if shouldFail { throw failError }
        lock.withLock { remoteTasks[task.id] = task }
    }

    func updateTask(_ task: Task) async throws {
        updateCallCount += 1
        if shouldFail { throw failError }
        lock.withLock { remoteTasks[task.id] = task }
    }

    func deleteTask(id: UUID) async throws {
        deleteCallCount += 1
        if shouldFail { throw failError }
        lock.withLock { remoteTasks[id] = nil }
    }

    func remoteTask(id: UUID) -> Task? {
        lock.withLock { remoteTasks[id] }
    }

    func seed(_ task: Task) {
        lock.withLock { remoteTasks[task.id] = task }
    }
}
