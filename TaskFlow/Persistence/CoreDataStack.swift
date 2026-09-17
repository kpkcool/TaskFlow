//
//  CoreDataStack.swift
//  TaskFlow
//
//  Core Data is the local source of truth. It must stay available even when
//  Firebase/network is unreachable, so store loading failures are handled
//  with a one-shot recovery attempt instead of crashing the app.
//

import CoreData
import Foundation
import os

final class CoreDataStack {

    static let shared = CoreDataStack()

    /// Set when the persistent store could not be loaded (even after the
    /// recovery attempt). The app keeps running; callers should surface this
    /// as a persistence error rather than lose user data silently.
    private(set) var loadError: Error?

    let persistentContainer: NSPersistentContainer

    /// Main-queue context, used for UI-facing fetches/observation only.
    /// Never written to directly outside of merges from background saves.
    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    /// - Parameter storeURL: Overrides where the SQLite store lives. Tests
    ///   use this to point two separate `CoreDataStack` instances at the
    ///   same file, simulating "quit and relaunch the app" without
    ///   depending on the app's real Application Support directory.
    init(inMemory: Bool = false, storeURL: URL? = nil) {
        let container = NSPersistentContainer(name: "TaskFlow")

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.url = URL(fileURLWithPath: "/dev/null")
            container.persistentStoreDescriptions = [description]
        } else if let storeURL {
            let description = NSPersistentStoreDescription(url: storeURL)
            container.persistentStoreDescriptions = [description]
        }

        var caughtError: Error?
        container.loadPersistentStores { storeDescription, error in
            if let error {
                AppLogger.persistence.error("Failed to load persistent store: \(error.localizedDescription, privacy: .public)")
                caughtError = error
            }
        }

        if caughtError != nil, !inMemory, let storeURL = container.persistentStoreDescriptions.first?.url {
            // Recovery attempt: the store may be corrupted from a previous
            // crash. Destroy it and start fresh rather than lose the ability
            // to run the app entirely. This does mean local data still on
            // disk in that corrupted file is lost, but a working app beats a
            // permanently crashing one; Firestore remains the backstop for
            // anything already synced.
            AppLogger.persistence.error("Attempting recovery: recreating persistent store")
            caughtError = nil
            try? container.persistentStoreCoordinator.destroyPersistentStore(at: storeURL, ofType: NSSQLiteStoreType)
            container.loadPersistentStores { _, error in
                if let error {
                    AppLogger.persistence.error("Recovery failed: \(error.localizedDescription, privacy: .public)")
                    caughtError = error
                }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        self.persistentContainer = container
        self.loadError = caughtError
    }

    /// A fresh background context for writes/sync work. Never touch the
    /// main thread with Core Data work; all mutations go through this.
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    /// Saves a context if it has changes, wrapping the throw so callers get
    /// a typed `TaskRepositoryError`.
    func save(_ context: NSManagedObjectContext) throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            AppLogger.persistence.error("Save failed: \(error.localizedDescription, privacy: .public)")
            throw TaskRepositoryError.persistenceFailed(error.localizedDescription)
        }
    }
}
