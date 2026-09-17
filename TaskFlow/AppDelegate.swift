//
//  AppDelegate.swift
//  TaskFlow
//

import UIKit
import os

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    /// Composition root for the whole app. SceneDelegate reads this to
    /// build the UI; kept on AppDelegate (not a global) so tests can spin
    /// up their own AppDependencies without touching this one.
    lazy var dependencies = AppDependencies()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseService.configureIfPossible()
        dependencies.start()
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }

    // MARK: - Core Data Saving support

    /// Defensive flush on backgrounding. In normal operation there should be
    /// nothing pending here — every mutation already saves its own
    /// background context immediately — but this guards against the
    /// unexpected without ever crashing.
    func saveContext() {
        do {
            try dependencies.coreDataStack.save(dependencies.coreDataStack.viewContext)
        } catch {
            AppLogger.persistence.error("saveContext failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
