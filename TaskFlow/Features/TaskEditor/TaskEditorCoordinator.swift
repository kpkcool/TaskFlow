//
//  TaskEditorCoordinator.swift
//  TaskFlow
//

import UIKit

final class TaskEditorCoordinator: Coordinator {

    var onFinish: (() -> Void)?

    private let navigationController: UINavigationController
    private let repository: TaskRepository
    private let task: Task?

    init(navigationController: UINavigationController, repository: TaskRepository, task: Task?) {
        self.navigationController = navigationController
        self.repository = repository
        self.task = task
    }

    func start() {
        let viewModel = TaskEditorViewModel(repository: repository, task: task)
        let viewController = TaskEditorViewController(viewModel: viewModel)
        viewController.onSaved = { [weak self] in self?.onFinish?() }
        viewController.onCancel = { [weak self] in self?.onFinish?() }
        viewController.onDeleted = { [weak self] in self?.onFinish?() }
        navigationController.setViewControllers([viewController], animated: false)
    }
}
