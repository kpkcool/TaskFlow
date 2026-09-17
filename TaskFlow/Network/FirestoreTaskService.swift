//
//  FirestoreTaskService.swift
//  TaskFlow
//
//  ONLY this file talks to Firestore. Everything else — ViewModels,
//  ViewControllers, the Repository's callers — only sees
//  FirestoreTaskServiceProtocol.
//
//  This file compiles two ways on purpose:
//   - With the Firebase SPM package added: real Firestore reads/writes.
//   - Without it (a fresh checkout before running `File > Add Package
//     Dependencies`): a stub that reports "network unavailable", so the
//     project builds and the offline-first path is fully exercisable even
//     before Firebase is wired up. See README for how to add the package.
//

import Foundation

protocol FirestoreTaskServiceProtocol: Sendable {
    func fetchTasks() async throws -> [Task]
    func createTask(_ task: Task) async throws
    func updateTask(_ task: Task) async throws
    func deleteTask(id: UUID) async throws
}

final class UnavailableFirestoreTaskService: FirestoreTaskServiceProtocol, @unchecked Sendable {

    init() {}

    func fetchTasks() async throws -> [Task] {
        throw TaskRepositoryError.networkUnavailable
    }

    func createTask(_ task: Task) async throws {
        throw TaskRepositoryError.networkUnavailable
    }

    func updateTask(_ task: Task) async throws {
        throw TaskRepositoryError.networkUnavailable
    }

    func deleteTask(id: UUID) async throws {
        throw TaskRepositoryError.networkUnavailable
    }
}

#if canImport(FirebaseFirestore)

import FirebaseFirestore

final class FirestoreTaskService: FirestoreTaskServiceProtocol, @unchecked Sendable {

    private let collection: CollectionReference

    init(firestore: Firestore) {
        collection = firestore.collection(AppConstants.firestoreTasksCollection)
    }

    convenience init() {
        self.init(firestore: Firestore.firestore())
    }

    func fetchTasks() async throws -> [Task] {
        do {
            let snapshot = try await collection.getDocuments(source: .server)
            return snapshot.documents.compactMap { Self.task(from: $0.data()) }
        } catch {
            throw TaskRepositoryError.syncFailed(error.localizedDescription)
        }
    }

    func createTask(_ task: Task) async throws {
        try await write(task)
    }

    /// Firestore's `setData` is an upsert, so update and create share the
    /// same call — a failed create simply becomes a create-on-retry.
    func updateTask(_ task: Task) async throws {
        try await write(task)
    }

    func deleteTask(id: UUID) async throws {
        do {
            try await collection.document(id.uuidString).delete()
        } catch {
            throw TaskRepositoryError.syncFailed(error.localizedDescription)
        }
    }

    private func write(_ task: Task) async throws {
        do {
            try await collection.document(task.id.uuidString).setData(Self.data(from: task))
        } catch {
            throw TaskRepositoryError.syncFailed(error.localizedDescription)
        }
    }

    private static func data(from task: Task) -> [String: Any] {
        [
            "id": task.id.uuidString,
            "title": task.title,
            "description": task.taskDescription,
            "status": task.status.rawValue,
            "createdAt": Timestamp(date: task.createdAt),
            "updatedAt": Timestamp(date: task.updatedAt),
            "sortOrder": task.sortOrder
        ]
    }

    private static func task(from data: [String: Any]) -> Task? {
        guard
            let idString = data["id"] as? String,
            let id = UUID(uuidString: idString),
            let title = data["title"] as? String,
            let description = data["description"] as? String,
            let statusRaw = data["status"] as? String,
            let status = TaskStatus(rawValue: statusRaw),
            let sortOrder = data["sortOrder"] as? Double
        else { return nil }

        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()

        return Task(
            id: id,
            title: title,
            taskDescription: description,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            sortOrder: sortOrder,
            syncStatus: .synced
        )
    }
}

// Every method throws .networkUnavailable, which is why tasks show the orange ⚠ sync badge
// and "Syncing N changes..." never succeeds.
// Once completed the Firebase integration steps in FirebaseService.swift,
// this entire #else block stops compiling and the real Firestore
// implementation above takes over automatically. No edits to this file needed.

#else

final class FirestoreTaskService: FirestoreTaskServiceProtocol, @unchecked Sendable {

    private let fallback = UnavailableFirestoreTaskService()

    init() {}

    func fetchTasks() async throws -> [Task] { try await fallback.fetchTasks() }

    func createTask(_ task: Task) async throws { try await fallback.createTask(task) }

    func updateTask(_ task: Task) async throws { try await fallback.updateTask(task) }

    func deleteTask(id: UUID) async throws { try await fallback.deleteTask(id: id) }
}

#endif
