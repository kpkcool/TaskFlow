//
//  AppDependencies.swift
//  TaskFlow
//
//  Composition root: the one place that knows Core Data and Firestore
//  exist, and wires them behind TaskRepository. Everything downstream
//  (Coordinators, ViewModels, ViewControllers) only ever sees the
//  TaskRepository protocol.
//
import Foundation

final class AppDependencies {

    let networkMonitor: NetworkMonitor
    let coreDataStack: CoreDataStack
    let localStore: TaskLocalStoreProtocol
    let remoteService: FirestoreTaskServiceProtocol
    let syncEngine: SyncEngine
    let repository: TaskRepository

    init(inMemory: Bool = false) {
        let stack = CoreDataStack(inMemory: inMemory)
        let store = CoreDataTaskStore(stack: stack)
        let remote: FirestoreTaskServiceProtocol

        if FirebaseService.isConfigured {
            remote = FirestoreTaskService()
        } else {
            remote = UnavailableFirestoreTaskService()
        }

        let engine = SyncEngine(localStore: store, remoteService: remote)

        self.coreDataStack = stack
        self.localStore = store
        self.remoteService = remote
        self.syncEngine = engine
        self.networkMonitor = .shared
        self.repository = TaskRepositoryImpl(localStore: store, syncEngine: engine)
    }

    /// Called once at launch. Starts watching for connectivity changes and
    /// feeds them to the SyncEngine — this is what makes "network comes
    /// back -> sync automatically" happen without any UI involvement.
    func start() {
        networkMonitor.startMonitoring()
        let engine = syncEngine
        let monitor = networkMonitor
        _Concurrency.Task.detached {
            for await isOnline in monitor.stream() {
                await engine.updateConnectivity(isOnline)
            }
        }
    }
}
