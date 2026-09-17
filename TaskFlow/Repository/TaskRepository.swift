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

    // MARK: Additions beyond the base spec
    //
    // The ViewModel is only given a TaskRepository (see AppCoordinator), yet
    // it also needs to render sync status and drive the debug screen. Rather
    // than reaching around the Repository to touch NetworkMonitor/SyncEngine
    // directly, both are surfaced here so the "ViewModel only knows about
    // Repository" rule holds without exception.

    /// High-level sync status (idle/offline/syncing/synced/failed).
    func observeSyncState() -> AsyncStream<SyncState>

    /// Number of tasks that still need to be pushed to Firestore.
    func pendingChangeCount() async -> Int

    /// Timestamp of the last completed sync pass, if any.
    func lastSyncDate() async -> Date?

    /// Debug-screen hook: wipes every local task. Does not touch Firestore.
    func clearAllLocalData() async throws
}
