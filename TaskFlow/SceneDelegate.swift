//
//  SceneDelegate.swift
//  TaskFlow
//
//  Entirely programmatic — no storyboard. Builds the window and hands off
//  to AppCoordinator immediately so the board (backed by already-cached
//  Core Data tasks) appears without waiting on anything network-related.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var appCoordinator: AppCoordinator?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        guard let dependencies = (UIApplication.shared.delegate as? AppDelegate)?.dependencies else { return }

        let window = UIWindow(windowScene: windowScene)
        let coordinator = AppCoordinator(window: window, repository: dependencies.repository)
        coordinator.start()

        self.window = window
        self.appCoordinator = coordinator
    }

    func sceneDidDisconnect(_ scene: UIScene) {
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // One of the required retry triggers: app becomes active.
        guard let repository = (UIApplication.shared.delegate as? AppDelegate)?.dependencies.repository else { return }
        _Concurrency.Task { await repository.syncPendingChanges() }
    }

    func sceneWillResignActive(_ scene: UIScene) {
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        (UIApplication.shared.delegate as? AppDelegate)?.saveContext()
    }
}
