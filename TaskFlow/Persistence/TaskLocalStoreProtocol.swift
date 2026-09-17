//
//  TaskLocalStoreProtocol.swift
//  TaskFlow
//
//  Narrow seam between the Repository and Core Data so tests can swap in
//  MockTaskStore without touching a real persistent store.
//

import Foundation

protocol TaskLocalStoreProtocol: AnyObject, Sendable {
    /// Live view of every locally-stored task (including ones pending
    /// deletion) ordered by sortOrder. Emits again on every local write.
    func observeTasks() -> AsyncStream<[Task]>

    func fetchAllTasks() async throws -> [Task]
    func fetchTask(id: UUID) async throws -> Task?

    /// Insert or update by id.
    func upsert(_ task: Task) async throws
    func upsertAll(_ tasks: [Task]) async throws

    /// Removes the row entirely. Only safe to call once a delete has been
    /// confirmed synced (or never existed remotely).
    func hardDelete(id: UUID) async throws

    /// Removes every row in a single Core Data save. Used for "Clear Local
    /// Data" — deleting N rows via N separate `hardDelete` calls fires N
    /// separate background-context saves, each independently and
    /// asynchronously merged into the main `viewContext` (and therefore N
    /// separate `NSFetchedResultsController` updates racing on the main run
    /// loop). Observers can end up rendering an intermediate state. One
    /// atomic delete removes that race entirely.
    func hardDeleteAll() async throws

    /// Tasks whose syncStatus is anything other than `.synced`.
    func fetchPendingSync() async throws -> [Task]
}
