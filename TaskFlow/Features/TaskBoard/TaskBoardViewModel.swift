//
//  TaskBoardViewModel.swift
//  TaskFlow
//
//  Depends only on TaskRepository — has no idea Core Data or Firestore
//  exist. Bridges the repository's AsyncStreams to @Published state the
//  ViewController renders.
//

import Combine
import Foundation
import UIKit

@MainActor
final class TaskBoardViewModel: ObservableObject {

    @Published private(set) var sections: [TaskSection] = TaskStatus.allCases.map { TaskSection(status: $0, tasks: []) }
    @Published private(set) var syncState: SyncState = .idle
    @Published var errorMessage: String?
    @Published private(set) var pendingChangeCount: Int = 0

    private let repository: TaskRepository
    private var observeTasksTask: _Concurrency.Task<Void, Never>?
    private var observeSyncTask: _Concurrency.Task<Void, Never>?

    init(repository: TaskRepository) {
        self.repository = repository
    }

    /// Idempotent — safe to call every time the board appears.
    func start() {
        if observeTasksTask == nil {
            observeTasksTask = _Concurrency.Task { [weak self] in
                guard let self else { return }
                for await tasks in repository.observeTasks() {
                    self.apply(tasks)
                }
            }
        }
        if observeSyncTask == nil {
            observeSyncTask = _Concurrency.Task { [weak self] in
                guard let self else { return }
                for await state in repository.observeSyncState() {
                    self.syncState = state
                    if case .failed(let message) = state {
                        self.errorMessage = message
                    }
                }
            }
        }
    }

    func stop() {
        observeTasksTask?.cancel()
        observeTasksTask = nil
        observeSyncTask?.cancel()
        observeSyncTask = nil
    }

    private func apply(_ tasks: [Task]) {
        sections = TaskStatus.allCases.map { status in
            let tasksInStatus = tasks
                .filter { $0.status == status }
                .sorted { $0.sortOrder < $1.sortOrder }
            return TaskSection(status: status, tasks: tasksInStatus)
        }
        pendingChangeCount = tasks.filter(\.syncStatus.isPending).count
    }

    // MARK: - Intents

    func task(at indexPath: IndexPath) -> Task? {
        guard sections.indices.contains(indexPath.section) else { return nil }
        let tasks = sections[indexPath.section].tasks
        guard tasks.indices.contains(indexPath.item) else { return nil }
        return tasks[indexPath.item]
    }

    func deleteTask(_ task: Task) {
        _Concurrency.Task { [weak self] in
            do {
                try await self?.repository.deleteTask(task)
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    /// Moves `task` to `status`, positioned at `targetIndex` within that
    /// section's current (post-move) task list. Used by both drag-and-drop
    /// and the "Move to..." context menu.
    func moveTask(_ task: Task, to status: TaskStatus, targetIndex: Int?) {
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                if task.status != status {
                    try await repository.moveTask(task, to: status)
                }
                guard let targetIndex else { return }

                let section = sections.first(where: { $0.status == status })
                let siblings = (section?.tasks ?? []).filter { $0.id != task.id }
                let before = targetIndex > 0 ? siblings[safe: targetIndex - 1]?.sortOrder : nil
                let after = siblings[safe: targetIndex]?.sortOrder

                if SortOrderCalculator.needsNormalization(before: before, after: after) {
                    // The gap between neighbors got too small for floating
                    // point math to safely split again — recompute clean,
                    // evenly-spaced values for the whole section (with
                    // `task` inserted at its new position) instead of a
                    // single midpoint that could collide.
                    var reordered = siblings
                    reordered.insert(task, at: min(targetIndex, siblings.count))
                    for renormalized in SortOrderCalculator.normalized(reordered) {
                        try await repository.reorderTask(renormalized, newSortOrder: renormalized.sortOrder)
                    }
                } else {
                    let newSortOrder = SortOrderCalculator.between(before: before, after: after)
                    try await repository.reorderTask(task, newSortOrder: newSortOrder)
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func retrySync() {
        _Concurrency.Task { [weak self] in
            await self?.repository.syncPendingChanges()
        }
    }

    /// Awaitable variant for pull-to-refresh: the caller needs to know when
    /// the attempt is over so it can stop the refresh spinner itself,
    /// rather than relying on the task list happening to change (it won't,
    /// if there was nothing to sync — which left the spinner stuck forever).
    func refreshAndWait() async {
        await repository.syncPendingChanges()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
