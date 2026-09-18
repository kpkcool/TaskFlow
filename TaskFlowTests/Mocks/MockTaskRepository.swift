//
//  MockTaskRepository.swift
//  TaskFlowTests
//
//  Lets ViewModel tests drive `sections`/`syncState`/`errorMessage` directly
//  without a real Repository, Core Data, or Firestore in the loop.
//

import Foundation
@testable import TaskFlow

final class MockTaskRepository: TaskRepository, @unchecked Sendable {
    private(set) var lastAction: String?
    private(set) var currentTasks: [Task] = []
    private var simulatedOffline = false
    private var connectivityContinuation: AsyncStream<Bool>.Continuation?

    var isOnline: Bool { !simulatedOffline }
    var isSimulatingOffline: Bool { simulatedOffline }

    var createTaskHandler: ((String, String) async throws -> Task)?
    var updateTaskHandler: ((Task) async throws -> Void)?
    var deleteTaskHandler: ((Task) async throws -> Void)?
    var moveTaskHandler: ((Task, TaskStatus) async throws -> Void)?
    var reorderTaskHandler: ((Task, Double) async throws -> Void)?

    private var tasksContinuation: AsyncStream<[Task]>.Continuation?
    private var syncContinuation: AsyncStream<SyncState>.Continuation?

    private lazy var tasksStream: AsyncStream<[Task]> = AsyncStream { [weak self] continuation in
        self?.tasksContinuation = continuation
        if let self { continuation.yield(self.currentTasks) }
    }

    private lazy var syncStream: AsyncStream<SyncState> = AsyncStream { [weak self] continuation in
        self?.syncContinuation = continuation
    }

    private lazy var connectivityStream: AsyncStream<Bool> = AsyncStream { [weak self] continuation in
        self?.connectivityContinuation = continuation
        if let self { continuation.yield(self.isOnline) }
    }

    func observeTasks() -> AsyncStream<[Task]> { tasksStream }
    func observeSyncState() -> AsyncStream<SyncState> { syncStream }
    func observeConnectivity() -> AsyncStream<Bool> { connectivityStream }

    func setSimulatedOffline(_ simulated: Bool) {
        simulatedOffline = simulated
        connectivityContinuation?.yield(isOnline)
    }

    func emitTasks(_ tasks: [Task]) {
        currentTasks = tasks
        tasksContinuation?.yield(tasks)
    }

    func emitSyncState(_ state: SyncState) {
        syncContinuation?.yield(state)
    }

    func createTask(title: String, description: String) async throws -> Task {
        lastAction = "create"
        if let handler = createTaskHandler {
            return try await handler(title, description)
        }
        return Task(title: title, taskDescription: description, status: .todo, sortOrder: 0, syncStatus: .pendingCreate)
    }

    func updateTask(_ task: Task) async throws {
        lastAction = "update"
        try await updateTaskHandler?(task)
    }

    func deleteTask(_ task: Task) async throws {
        lastAction = "delete"
        try await deleteTaskHandler?(task)
    }

    func moveTask(_ task: Task, to status: TaskStatus) async throws {
        lastAction = "move"
        try await moveTaskHandler?(task, status)
    }

    func reorderTask(_ task: Task, newSortOrder: Double) async throws {
        lastAction = "reorder"
        try await reorderTaskHandler?(task, newSortOrder)
    }

    func syncPendingChanges() async {
        lastAction = "sync"
    }
    
    func triggerSync() {
        lastAction = "triggerSync"
    }

    func pendingChangeCount() async -> Int {
        currentTasks.filter(\.syncStatus.isPending).count
    }

    func lastSyncDate() async -> Date? {
        nil
    }

    func clearAllLocalData() async throws {
        currentTasks = []
    }
}
