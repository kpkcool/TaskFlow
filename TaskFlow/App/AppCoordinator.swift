//
//  AppCoordinator.swift
//  TaskFlow
//

import UIKit

final class AppCoordinator: Coordinator {

    private let window: UIWindow
    private let repository: TaskRepository
    private var childCoordinators: [Coordinator] = []

    init(window: UIWindow, repository: TaskRepository) {
        self.window = window
        self.repository = repository
    }

    func start() {
        let navigationController = UINavigationController()
        navigationController.navigationBar.prefersLargeTitles = true

        let boardCoordinator = TaskBoardCoordinator(
            navigationController: navigationController,
            repository: repository
        )
        childCoordinators = [boardCoordinator]
        boardCoordinator.start()

        window.rootViewController = navigationController
        window.makeKeyAndVisible()
    }
}
