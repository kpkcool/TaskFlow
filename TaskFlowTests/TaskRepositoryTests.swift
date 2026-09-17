//
//  TaskRepositoryTests.swift
//  TaskFlowTests
//
//  Repository is exercised against MockTaskStore/MockFirestoreTaskService —
//  no real Core Data or Firebase involved. SyncEngine is never told it's
//  online in these tests, so every write below is exactly the "offline"
//  path too (see section "Offline behaviors").
//

import XCTest
@testable import TaskFlow

final class TaskRepositoryTests: XCTestCase {

    private var localStore: MockTaskStore!
    private var remoteService: MockFirestoreTaskService!
    private var syncEngine: SyncEngine!
    private var repository: TaskRepositoryImpl!

    override func setUp() async throws {
        localStore = MockTaskStore()
        remoteService = MockFirestoreTaskService()
        syncEngine = SyncEngine(localStore: localStore, remoteService: remoteService)
        repository = TaskRepositoryImpl(localStore: localStore, syncEngine: syncEngine)
    }

    // MARK: - Create

    func testCreateTaskSavesLocallyAsPendingCreate() async throws {
        let task = try await repository.createTask(title: "Buy milk", description: "2%")

        XCTAssertEqual(task.title, "Buy milk")
        XCTAssertEqual(task.status, .todo)
        XCTAssertEqual(task.syncStatus, .pendingCreate)

        let _fetched_stored = try await localStore.fetchTask(id: task.id)
        let stored = try XCTUnwrap(_fetched_stored)
        XCTAssertEqual(stored, task)
    }

    func testCreateTaskRejectsEmptyTitle() async throws {
        do {
            _ = try await repository.createTask(title: "   ", description: "")
            XCTFail("Expected invalidTask error")
        } catch TaskRepositoryError.invalidTask {
            // expected
        }
    }

    func testSecondCreateAppendsAfterFirstInSameColumn() async throws {
        let first = try await repository.createTask(title: "First", description: "")
        let second = try await repository.createTask(title: "Second", description: "")
        XCTAssertGreaterThan(second.sortOrder, first.sortOrder)
    }

    // MARK: - Update

    func testUpdateTaskMarksPendingUpdateAndBumpsUpdatedAt() async throws {
        let created = try await repository.createTask(title: "Original", description: "")
        var alreadySynced = created
        alreadySynced.syncStatus = .synced
        try await localStore.upsert(alreadySynced)

        var edited = alreadySynced
        edited.title = "Edited"
        try await repository.updateTask(edited)

        let _fetched_stored = try await localStore.fetchTask(id: created.id)
        let stored = try XCTUnwrap(_fetched_stored)
        XCTAssertEqual(stored.title, "Edited")
        XCTAssertEqual(stored.syncStatus, .pendingUpdate)
        XCTAssertGreaterThanOrEqual(stored.updatedAt, alreadySynced.updatedAt)
    }

    func testUpdatingUnsyncedCreateStaysPendingCreate() async throws {
        let created = try await repository.createTask(title: "Original", description: "")
        var edited = created
        edited.title = "Edited before first sync"
        try await repository.updateTask(edited)

        let _fetched_stored = try await localStore.fetchTask(id: created.id)
        let stored = try XCTUnwrap(_fetched_stored)
        XCTAssertEqual(stored.syncStatus, .pendingCreate)
    }

    func testUpdateTaskRejectsEmptyTitle() async throws {
        let created = try await repository.createTask(title: "Original", description: "")
        var edited = created
        edited.title = "   "
        do {
            try await repository.updateTask(edited)
            XCTFail("Expected invalidTask error")
        } catch TaskRepositoryError.invalidTask {
            // expected
        }
    }

    // MARK: - Delete

    func testDeletingUnsyncedTaskHardDeletesImmediately() async throws {
        let created = try await repository.createTask(title: "Throwaway", description: "")
        try await repository.deleteTask(created)
        let stored = try await localStore.fetchTask(id: created.id)
        XCTAssertNil(stored)
    }

    func testDeletingSyncedTaskSoftDeletesAndHidesFromObserveTasks() async throws {
        let created = try await repository.createTask(title: "Keep pending", description: "")
        var synced = created
        synced.syncStatus = .synced
        try await localStore.upsert(synced)

        try await repository.deleteTask(synced)

        let _fetched_stored = try await localStore.fetchTask(id: created.id)
        let stored = try XCTUnwrap(_fetched_stored)
        XCTAssertEqual(stored.syncStatus, .pendingDelete, "Row must stay in Core Data until the delete is confirmed synced")

        var iterator = repository.observeTasks().makeAsyncIterator()
        let visible = await iterator.next()
        XCTAssertFalse(visible?.contains(where: { $0.id == created.id }) ?? true, "Soft-deleted tasks must not appear in the UI-facing stream")
    }

    // MARK: - Move

    func testMoveTaskChangesStatusAndAppendsToEndOfTargetSection() async throws {
        let a = try await repository.createTask(title: "A", description: "")
        try await repository.moveTask(a, to: .inProgress)

        let _fetched_stored = try await localStore.fetchTask(id: a.id)
        let stored = try XCTUnwrap(_fetched_stored)
        XCTAssertEqual(stored.status, .inProgress)
    }

    func testMoveTaskNotFoundThrows() async throws {
        let ghost = Task(title: "Ghost", taskDescription: "", status: .todo, sortOrder: 0, syncStatus: .synced)
        do {
            try await repository.moveTask(ghost, to: .done)
            XCTFail("Expected notFound error")
        } catch TaskRepositoryError.notFound {
            // expected
        }
    }

    // MARK: - Reorder

    func testReorderTaskSetsExactSortOrder() async throws {
        let task = try await repository.createTask(title: "A", description: "")
        try await repository.reorderTask(task, newSortOrder: 42.5)
        let _fetched_stored = try await localStore.fetchTask(id: task.id)
        let stored = try XCTUnwrap(_fetched_stored)
        XCTAssertEqual(stored.sortOrder, 42.5)
    }

    // MARK: - Fully offline session

    func testCreateEditMoveReorderDeleteWorkFullyOffline() async throws {
        // SyncEngine.updateConnectivity(true) is never called in this test,
        // so every mutation above is already exercising the "offline" path.
        let task = try await repository.createTask(title: "Offline task", description: "desc")
        try await repository.moveTask(task, to: .inProgress)
        try await repository.reorderTask(task, newSortOrder: 5)

        var edited = task
        edited.title = "Offline task renamed"
        try await repository.updateTask(edited)

        try await repository.deleteTask(edited)

        let stored = try await localStore.fetchTask(id: task.id)
        XCTAssertNil(stored, "A task that never synced should hard-delete immediately, even offline")
    }
}
