//
//  CoreDataPersistenceTests.swift
//  TaskFlowTests
//
//  Exercises the *real* Core Data stack (not a mock) against a throwaway
//  on-disk SQLite file, tearing the stack down and rebuilding a brand new
//  one pointed at the same file — the closest a unit test can get to
//  "quit the app and relaunch it" without UI automation.
//

import XCTest
@testable import TaskFlow

final class CoreDataPersistenceTests: XCTestCase {

    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskFlowTests-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
    }

    func testTasksSurviveRelaunch() async throws {
        let task = Task(title: "Survive relaunch", taskDescription: "desc", status: .inProgress, sortOrder: 7, syncStatus: .pendingCreate)

        // "First launch": write a task and let the stack go away.
        do {
            let stack = CoreDataStack(storeURL: storeURL)
            let store = CoreDataTaskStore(stack: stack)
            try await store.upsert(task)
            let stored = try await store.fetchTask(id: task.id)
            XCTAssertNotNil(stored, "Sanity check: task exists before relaunch")
        }

        // "Relaunch": a brand-new stack/store pointed at the same file.
        let stack = CoreDataStack(storeURL: storeURL)
        let store = CoreDataTaskStore(stack: stack)
        let reloaded = try await store.fetchTask(id: task.id)

        XCTAssertEqual(reloaded?.title, "Survive relaunch")
        XCTAssertEqual(reloaded?.status, .inProgress)
        XCTAssertEqual(reloaded?.syncStatus, .pendingCreate)
        XCTAssertEqual(reloaded?.sortOrder, 7)
    }

    func testPendingChangesSurviveRelaunchForLaterSync() async throws {
        let pending = Task(title: "Still needs sync", taskDescription: "", status: .todo, sortOrder: 1, syncStatus: .pendingCreate)

        do {
            let stack = CoreDataStack(storeURL: storeURL)
            let store = CoreDataTaskStore(stack: stack)
            try await store.upsert(pending)
        }

        let stack = CoreDataStack(storeURL: storeURL)
        let store = CoreDataTaskStore(stack: stack)
        let pendingAfterRelaunch = try await store.fetchPendingSync()

        XCTAssertEqual(pendingAfterRelaunch.count, 1)
        XCTAssertEqual(pendingAfterRelaunch.first?.id, pending.id)
    }
}
