//
//  TaskRepository.swift
//  TaskFlow
//
//  The only boundary ViewModels are allowed to depend on. Nothing above
//  this protocol knows Core Data or Firebase exist.
//
import Foundation

protocol TaskRepository: Sendable {
    func observeTasks() -> AsyncStream<[Task]>
    func createTask(title: String, description: String) async throws -> Task
    func updateTask(_ task: Task) async throws
    func deleteTask(_ task: Task) async throws
    func moveTask(_ task: Task, to status: TaskStatus) async throws
    func reorderTask(_ task: Task, newSortOrder: Double) async throws
    func syncPendingChanges() async
    func triggerSync()
    
    /// High-level sync status (idle/offline/syncing/synced/failed).
    /// Each caller gets an independent stream that replays the current
    /// state immediately — safe for multiple simultaneous observers.
    func observeSyncState() -> AsyncStream<SyncState>

    /// Live connectivity, including the debug "simulate offline" override.
    /// Replays the current value on subscribe.
    func observeConnectivity() -> AsyncStream<Bool>

    /// Current connectivity without subscribing.
    var isOnline: Bool { get }

    /// Debug-screen hook: forces the app to behave as if offline.
    func setSimulatedOffline(_ simulated: Bool)

    /// Whether the debug offline override is currently engaged.
    var isSimulatingOffline: Bool { get }

    /// Number of tasks that still need to be pushed to Firestore.
    func pendingChangeCount() async -> Int

    /// Timestamp of the last completed sync pass, if any.
    func lastSyncDate() async -> Date?

    /// Debug-screen hook: wipes every local task. Does not touch Firestore.
    func clearAllLocalData() async throws
}
