//
//  TaskBoardCoordinator.swift
//  TaskFlow
//
//  Owns navigation for the board screen: presenting the editor (for create
//  and edit) and the debug screen. The ViewController never pushes/presents
//  anything itself — it only calls closures this coordinator sets.
//

import UIKit

final class TaskBoardCoordinator: Coordinator {

    private let navigationController: UINavigationController
    private let repository: TaskRepository
    private var childCoordinators: [Coordinator] = []

    init(navigationController: UINavigationController, repository: TaskRepository) {
        self.navigationController = navigationController
        self.repository = repository
    }

    func start() {
        let viewModel = TaskBoardViewModel(repository: repository)
        let viewController = TaskBoardViewController(viewModel: viewModel)

        viewController.onAddTask = { [weak self] in
            self?.presentEditor(for: nil)
        }
        viewController.onSelectTask = { [weak self] task in
            self?.presentEditor(for: task)
        }
        viewController.onOpenDebug = { [weak self] in
            self?.presentDebug()
        }

        navigationController.setViewControllers([viewController], animated: false)
    }

    private func presentEditor(for task: Task?) {
        let editorNavigationController = UINavigationController()
        let coordinator = TaskEditorCoordinator(
            navigationController: editorNavigationController,
            repository: repository,
            task: task
        )
        coordinator.onFinish = { [weak self, weak coordinator] in
            self?.navigationController.presentedViewController?.dismiss(animated: true)
            if let coordinator {
                self?.childCoordinators.removeAll { $0 === coordinator }
            }
        }
        childCoordinators.append(coordinator)
        coordinator.start()
        editorNavigationController.modalPresentationStyle = .formSheet
        navigationController.present(editorNavigationController, animated: true)
    }

    private func presentDebug() {
        let debugViewController = DebugViewController(repository: repository)
        let debugNavigationController = UINavigationController(rootViewController: debugViewController)
        debugViewController.onDone = { [weak self] in
            self?.navigationController.presentedViewController?.dismiss(animated: true)
        }
        navigationController.present(debugNavigationController, animated: true)
    }
}
