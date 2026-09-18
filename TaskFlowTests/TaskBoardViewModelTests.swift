//
//  TaskBoardViewModelTests.swift
//  TaskFlowTests
//
//  Drives TaskBoardViewModel purely through MockTaskRepository — no Core
//  Data, no Firebase, no real async streams beyond what the mock emits.
//

import Combine
import XCTest
@testable import TaskFlow

@MainActor
final class TaskBoardViewModelTests: XCTestCase {

    private var repository: MockTaskRepository!
    private var viewModel: TaskBoardViewModel!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()

        repository = MockTaskRepository()
        viewModel = TaskBoardViewModel(repository: repository)
        cancellables = []
    }

    override func tearDown() {
        viewModel.stop()

        cancellables.removeAll()
        viewModel = nil
        repository = nil

        super.tearDown()
    }

    // MARK: - Sections

    func testSectionsGroupAndSortTasksByStatusAndSortOrder() async throws {
        viewModel.start()

        // Give the ViewModel's observation Task a chance to
        // subscribe to the repository stream.
        await _Concurrency.Task.yield()

        let todoA = Task(
            title: "Todo B",
            taskDescription: "",
            status: .todo,
            sortOrder: 20,
            syncStatus: .synced
        )

        let todoB = Task(
            title: "Todo A",
            taskDescription: "",
            status: .todo,
            sortOrder: 10,
            syncStatus: .synced
        )

        let inProgress = Task(
            title: "Doing",
            taskDescription: "",
            status: .inProgress,
            sortOrder: 5,
            syncStatus: .synced
        )

        let expectation = expectation(
            description: "sections updated"
        )

        viewModel.$sections
            .dropFirst()
            .sink { sections in
                let todoTitles = sections
                    .first(where: { $0.status == .todo })?
                    .tasks
                    .map(\.title)

                if todoTitles == ["Todo A", "Todo B"] {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        repository.emitTasks([
            todoA,
            todoB,
            inProgress
        ])

        await fulfillment(
            of: [expectation],
            timeout: 2
        )

        let inProgressTitles = viewModel.sections
            .first(where: { $0.status == .inProgress })?
            .tasks
            .map(\.title)

        XCTAssertEqual(
            inProgressTitles,
            ["Doing"]
        )
    }

    // MARK: - Sync State

    func testSyncStateReflectsRepositoryStream() async throws {
        // Force the mock's sync stream to be created first.
        _ = repository.observeSyncState()

        viewModel.start()

        let expectation = expectation(
            description: "sync state updated"
        )

        viewModel.$syncState
            .dropFirst()
            .sink { state in
                if case .syncing(let count) = state, count == 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        repository.emitSyncState(
            .syncing(pendingCount: 3)
        )

        await fulfillment(
            of: [expectation],
            timeout: 2
        )

        if case .syncing(let count) = viewModel.syncState {
            XCTAssertEqual(count, 3)
        } else {
            XCTFail("Expected syncState to be .syncing(3)")
        }
    }

    // MARK: - Failed Sync

    func testFailedSyncStateReflectsRepositoryStream() async throws {
        viewModel.start()

        // Allow the observation Task to subscribe first.
        await _Concurrency.Task.yield()

        let expectation = expectation(
            description: "failed sync state updated"
        )

        viewModel.$syncState
            .dropFirst()
            .sink { state in
                guard case .failed(let message) = state else {
                    return
                }

                if message == "Offline for too long" {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        repository.emitSyncState(
            .failed("Offline for too long")
        )

        await fulfillment(
            of: [expectation],
            timeout: 2
        )

        // The ViewModel intentionally stores the failure
        // in syncState, not errorMessage.
        guard case .failed(let message) = viewModel.syncState else {
            XCTFail("Expected failed sync state")
            return
        }

        XCTAssertEqual(
            message,
            "Offline for too long"
        )
    }

    // MARK: - Delete

    func testDeleteTaskDelegatesToRepository() async throws {
        let task = Task(
            title: "Delete me",
            taskDescription: "",
            status: .todo,
            sortOrder: 1,
            syncStatus: .synced
        )

        let expectation = expectation(
            description: "delete called"
        )

        repository.deleteTaskHandler = { deleted in
            XCTAssertEqual(
                deleted.id,
                task.id
            )

            expectation.fulfill()
        }

        viewModel.deleteTask(task)

        await fulfillment(
            of: [expectation],
            timeout: 2
        )
    }
}
