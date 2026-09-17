//
//  SyncEngineTests.swift
//  TaskFlowTests
//

import XCTest
@testable import TaskFlow

final class SyncEngineTests: XCTestCase {

    private var localStore: MockTaskStore!
    private var remoteService: MockFirestoreTaskService!
    private var syncEngine: SyncEngine!

    override func setUp() async throws {
        localStore = MockTaskStore()
        remoteService = MockFirestoreTaskService()
        syncEngine = SyncEngine(localStore: localStore, remoteService: remoteService)
        await syncEngine.updateConnectivity(true)
    }

    func testPendingCreateSyncsAndBecomesSynced() async throws {
        let task = Task(title: "New", taskDescription: "", status: .todo, sortOrder: 1, syncStatus: .pendingCreate)
        try await localStore.upsert(task)

        await syncEngine.syncNow()

        let _fetched_stored = try await localStore.fetchTask(id: task.id)
        let stored = try XCTUnwrap(_fetched_stored)
        XCTAssertEqual(stored.syncStatus, .synced)
        XCTAssertNotNil(remoteService.remoteTask(id: task.id))
    }

    func testPendingUpdateSyncs() async throws {
        var task = Task(title: "Existing", taskDescription: "", status: .todo, sortOrder: 1, syncStatus: .synced)
        remoteService.seed(task)
        try await localStore.upsert(task)

        task.title = "Edited"
        task.syncStatus = .pendingUpdate
        try await localStore.upsert(task)

        await syncEngine.syncNow()

        let _fetched_stored = try await localStore.fetchTask(id: task.id)
        let stored = try XCTUnwrap(_fetched_stored)
        XCTAssertEqual(stored.syncStatus, .synced)
        XCTAssertEqual(remoteService.remoteTask(id: task.id)?.title, "Edited")
    }

    func testPendingDeleteSyncsAndHardDeletesLocally() async throws {
        let task = Task(title: "Doomed", taskDescription: "", status: .todo, sortOrder: 1, syncStatus: .synced)
        remoteService.seed(task)
        try await localStore.upsert(task)

        var pendingDelete = task
        pendingDelete.syncStatus = .pendingDelete
        try await localStore.upsert(pendingDelete)

        await syncEngine.syncNow()

        let stored = try await localStore.fetchTask(id: task.id)
        XCTAssertNil(stored, "Row should be hard-deleted once the remote delete succeeds")
        XCTAssertNil(remoteService.remoteTask(id: task.id))
    }

    func testFirebaseFailureKeepsLocalDataAndMarksFailed() async throws {
        remoteService.shouldFail = true
        let task = Task(title: "Will fail", taskDescription: "", status: .todo, sortOrder: 1, syncStatus: .pendingCreate)
        try await localStore.upsert(task)

        await syncEngine.syncNow()

        let _fetched_stored = try await localStore.fetchTask(id: task.id)
        let stored = try XCTUnwrap(_fetched_stored)
        XCTAssertEqual(stored.syncStatus, .failed, "A failed sync must never lose the task — it stays local and retryable")
        XCTAssertEqual(stored.title, "Will fail")
    }

    func testFailedDeleteStaysPendingDeleteNotFailed() async throws {
        remoteService.shouldFail = true
        let task = Task(title: "Doomed", taskDescription: "", status: .todo, sortOrder: 1, syncStatus: .synced)
        remoteService.seed(task)
        try await localStore.upsert(task)

        var pendingDelete = task
        pendingDelete.syncStatus = .pendingDelete
        try await localStore.upsert(pendingDelete)

        await syncEngine.syncNow()

        let _fetched_stored = try await localStore.fetchTask(id: task.id)
        let stored = try XCTUnwrap(_fetched_stored)
        XCTAssertEqual(stored.syncStatus, .pendingDelete, "A failed delete must not be reinterpreted as a create/update on retry")
    }

    func testRetrySucceedsAfterTransientFailure() async throws {
        remoteService.shouldFail = true
        let task = Task(title: "Retry me", taskDescription: "", status: .todo, sortOrder: 1, syncStatus: .pendingCreate)
        try await localStore.upsert(task)

        await syncEngine.syncNow()
        let _fetched_stored = try await localStore.fetchTask(id: task.id)
        var stored = try XCTUnwrap(_fetched_stored)
        XCTAssertEqual(stored.syncStatus, .failed)

        remoteService.shouldFail = false
        await syncEngine.syncNow()

        let _fetched_stored2 = try await localStore.fetchTask(id: task.id)
        stored = try XCTUnwrap(_fetched_stored2)
        XCTAssertEqual(stored.syncStatus, .synced)
        XCTAssertNotNil(remoteService.remoteTask(id: task.id))
    }

    // MARK: - Conflict resolution: last-updated-wins

    func testConflictLocalNewerKeepsLocalAndReuploads() async throws {
        let older = Date(timeIntervalSinceNow: -100)
        let newer = Date()

        let remote = Task(title: "Remote copy", taskDescription: "", status: .todo, createdAt: older, updatedAt: older, sortOrder: 1, syncStatus: .synced)
        remoteService.seed(remote)

        var local = remote
        local.title = "Local edit (newer)"
        local.updatedAt = newer
        local.syncStatus = .pendingUpdate
        try await localStore.upsert(local)

        await syncEngine.syncNow()

        let _fetched_stored = try await localStore.fetchTask(id: local.id)
        let stored = try XCTUnwrap(_fetched_stored)
        XCTAssertEqual(stored.title, "Local edit (newer)")
        XCTAssertEqual(remoteService.remoteTask(id: local.id)?.title, "Local edit (newer)", "Newer local edit should have been pushed to Firestore")
    }

    func testConflictRemoteNewerOverwritesLocal() async throws {
        let older = Date(timeIntervalSinceNow: -100)
        let newer = Date()

        let local = Task(title: "Local edit (stale)", taskDescription: "", status: .todo, createdAt: older, updatedAt: older, sortOrder: 1, syncStatus: .pendingUpdate)
        try await localStore.upsert(local)

        var remote = local
        remote.title = "Remote edit (newer)"
        remote.updatedAt = newer
        remote.syncStatus = .synced
        remoteService.seed(remote)

        await syncEngine.syncNow()

        let _fetched_stored = try await localStore.fetchTask(id: local.id)
        let stored = try XCTUnwrap(_fetched_stored)
        XCTAssertEqual(stored.title, "Remote edit (newer)")
        XCTAssertEqual(stored.syncStatus, .synced)
    }

    func testRemoteDeleteOfSyncedTaskRemovesItLocally() async throws {
        let task = Task(title: "Deleted elsewhere", taskDescription: "", status: .todo, sortOrder: 1, syncStatus: .synced)
        try await localStore.upsert(task)
        // Not seeded remotely -> looks exactly like another client deleted it.

        await syncEngine.syncNow()

        let stored = try await localStore.fetchTask(id: task.id)
        XCTAssertNil(stored)
    }
}
