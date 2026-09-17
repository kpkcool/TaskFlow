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
        repository = MockTaskRepository()
        viewModel = TaskBoardViewModel(repository: repository)
        cancellables = []
    }

    override func tearDown() {
        viewModel.stop()
    }

    func testSectionsGroupAndSortTasksByStatusAndSortOrder() async throws {
        viewModel.start()

        let todoA = Task(title: "Todo B", taskDescription: "", status: .todo, sortOrder: 20, syncStatus: .synced)
        let todoB = Task(title: "Todo A", taskDescription: "", status: .todo, sortOrder: 10, syncStatus: .synced)
        let inProgress = Task(title: "Doing", taskDescription: "", status: .inProgress, sortOrder: 5, syncStatus: .synced)

        let expectation = expectation(description: "sections updated")
        viewModel.$sections
            .dropFirst() // skip the initial empty sections
            .sink { sections in
                let todoTitles = sections.first(where: { $0.status == .todo })?.tasks.map(\.title)
                if todoTitles == ["Todo A", "Todo B"] {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        repository.emitTasks([todoA, todoB, inProgress])
        await fulfillment(of: [expectation], timeout: 2)

        XCTAssertEqual(viewModel.sections.first(where: { $0.status == .inProgress })?.tasks.map(\.title), ["Doing"])
    }

    func testSyncStateReflectsRepositoryStream() async throws {
        viewModel.start()

        let expectation = expectation(description: "sync state updated")
        viewModel.$syncState
            .dropFirst()
            .sink { state in
                if case .syncing(let count) = state, count == 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        repository.emitSyncState(.syncing(pendingCount: 3))
        await fulfillment(of: [expectation], timeout: 2)
    }

    func testFailedSyncStatePopulatesErrorMessage() async throws {
        viewModel.start()

        let expectation = expectation(description: "error message set")
        viewModel.$errorMessage
            .compactMap { $0 }
            .sink { message in
                XCTAssertEqual(message, "Offline for too long")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        repository.emitSyncState(.failed("Offline for too long"))
        await fulfillment(of: [expectation], timeout: 2)
    }

    func testDeleteTaskDelegatesToRepository() async throws {
        let task = Task(title: "Delete me", taskDescription: "", status: .todo, sortOrder: 1, syncStatus: .synced)

        let expectation = expectation(description: "delete called")
        repository.deleteTaskHandler = { deleted in
            XCTAssertEqual(deleted.id, task.id)
            expectation.fulfill()
        }

        viewModel.deleteTask(task)
        await fulfillment(of: [expectation], timeout: 2)
    }
}
