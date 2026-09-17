//
//  TaskEditorViewModel.swift
//  TaskFlow
//
//  Same rule as the board: depends only on TaskRepository.
//

import Combine
import Foundation

@MainActor
final class TaskEditorViewModel: ObservableObject {

    @Published var title: String
    @Published var taskDescription: String
    @Published var status: TaskStatus
    @Published private(set) var validationError: String?
    @Published private(set) var isSaving = false

    private let repository: TaskRepository
    private let existingTask: Task?

    var isEditing: Bool { existingTask != nil }
    var navigationTitle: String { isEditing ? "Edit Task" : "New Task" }

    init(repository: TaskRepository, task: Task?) {
        self.repository = repository
        self.existingTask = task
        self.title = task?.title ?? ""
        self.taskDescription = task?.taskDescription ?? ""
        self.status = task?.status ?? .todo
    }

    func deleteTask(completion: @escaping (Bool) -> Void) {
        guard let task = existingTask else { return }
        _Concurrency.Task { [weak self] in
            do {
                try await self?.repository.deleteTask(task)
                completion(true)
            } catch {
                self?.validationError = error.localizedDescription
                completion(false)
            }
        }
    }

    func save(completion: @escaping (Bool) -> Void) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            validationError = "Title cannot be empty"
            return
        }
        validationError = nil
        isSaving = true

        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                if var task = self.existingTask {
                    task.title = trimmedTitle
                    task.taskDescription = self.taskDescription
                    task.status = self.status
                    try await self.repository.updateTask(task)
                } else {
                    let created = try await self.repository.createTask(
                        title: trimmedTitle,
                        description: self.taskDescription
                    )
                    if self.status != .todo {
                        try await self.repository.moveTask(created, to: self.status)
                    }
                }
                self.isSaving = false
                completion(true)
            } catch {
                self.isSaving = false
                self.validationError = error.localizedDescription
                completion(false)
            }
        }
    }
}
