//
//  CoreDataTaskStore.swift
//  TaskFlow
//
//  Core Data implementation of TaskLocalStoreProtocol. All mutations run on
//  a background context via the async `perform` API so the main thread is
//  never blocked; observation is powered by an NSFetchedResultsController on
//  the main viewContext (which auto-merges background saves).
//

import CoreData
import Foundation
import os

final class CoreDataTaskStore: TaskLocalStoreProtocol, @unchecked Sendable {

    private let stack: CoreDataStack

    init(stack: CoreDataStack = .shared) {
        self.stack = stack
    }

    func observeTasks() -> AsyncStream<[Task]> {
        AsyncStream { continuation in
            DispatchQueue.main.async { [stack] in
                let streamer = FetchedResultsStreamer(context: stack.viewContext, continuation: continuation)
                streamer.start()
                continuation.onTermination = { _ in
                    streamer.stop()
                }
            }
        }
    }

    func fetchAllTasks() async throws -> [Task] {
        let context = stack.newBackgroundContext()
        do {
            return try await context.perform {
                let request = TaskEntity.fetchRequest()
                request.sortDescriptors = [NSSortDescriptor(keyPath: \TaskEntity.sortOrder, ascending: true)]
                return try context.fetch(request).map { $0.toDomain() }
            }
        } catch {
            throw TaskRepositoryError.persistenceFailed(error.localizedDescription)
        }
    }

    func fetchTask(id: UUID) async throws -> Task? {
        let context = stack.newBackgroundContext()
        do {
            return try await context.perform {
                let request = TaskEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                request.fetchLimit = 1
                return try context.fetch(request).first?.toDomain()
            }
        } catch {
            throw TaskRepositoryError.persistenceFailed(error.localizedDescription)
        }
    }

    func fetchPendingSync() async throws -> [Task] {
        let context = stack.newBackgroundContext()
        do {
            return try await context.perform {
                let request = TaskEntity.fetchRequest()
                request.predicate = NSPredicate(format: "syncStatus != %@", SyncStatus.synced.rawValue)
                request.sortDescriptors = [NSSortDescriptor(keyPath: \TaskEntity.updatedAt, ascending: true)]
                return try context.fetch(request).map { $0.toDomain() }
            }
        } catch {
            throw TaskRepositoryError.persistenceFailed(error.localizedDescription)
        }
    }

    func upsert(_ task: Task) async throws {
        let context = stack.newBackgroundContext()
        do {
            try await context.perform {
                let entity = try Self.findOrCreate(id: task.id, in: context)
                entity.update(from: task)
                try self.stack.save(context)
            }
        } catch let error as TaskRepositoryError {
            throw error
        } catch {
            throw TaskRepositoryError.persistenceFailed(error.localizedDescription)
        }
    }

    func upsertAll(_ tasks: [Task]) async throws {
        let context = stack.newBackgroundContext()
        do {
            try await context.perform {
                for task in tasks {
                    let entity = try Self.findOrCreate(id: task.id, in: context)
                    entity.update(from: task)
                }
                try self.stack.save(context)
            }
        } catch let error as TaskRepositoryError {
            throw error
        } catch {
            throw TaskRepositoryError.persistenceFailed(error.localizedDescription)
        }
    }

    func hardDelete(id: UUID) async throws {
        let context = stack.newBackgroundContext()
        do {
            try await context.perform {
                let request = TaskEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                request.fetchLimit = 1
                if let entity = try context.fetch(request).first {
                    context.delete(entity)
                }
                try self.stack.save(context)
            }
        } catch let error as TaskRepositoryError {
            throw error
        } catch {
            throw TaskRepositoryError.persistenceFailed(error.localizedDescription)
        }
    }

    func hardDeleteAll() async throws {
        let context = stack.newBackgroundContext()
        do {
            try await context.perform {
                let request = TaskEntity.fetchRequest()
                let entities = try context.fetch(request)
                for entity in entities {
                    context.delete(entity)
                }
                try self.stack.save(context)
            }
        } catch let error as TaskRepositoryError {
            throw error
        } catch {
            throw TaskRepositoryError.persistenceFailed(error.localizedDescription)
        }
    }

    private static func findOrCreate(id: UUID, in context: NSManagedObjectContext) throws -> TaskEntity {
        let request = TaskEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first {
            return existing
        }
        return TaskEntity(context: context)
    }
}

/// Bridges NSFetchedResultsController's delegate callbacks into an
/// AsyncStream. Lives entirely on the main queue, matching the main-queue
/// `viewContext` it observes.
private final class FetchedResultsStreamer: NSObject, NSFetchedResultsControllerDelegate {
    private let controller: NSFetchedResultsController<TaskEntity>
    private let continuation: AsyncStream<[Task]>.Continuation

    init(context: NSManagedObjectContext, continuation: AsyncStream<[Task]>.Continuation) {
        let request = TaskEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TaskEntity.sortOrder, ascending: true)]
        controller = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        self.continuation = continuation
        super.init()
        controller.delegate = self
    }

    func start() {
        do {
            try controller.performFetch()
            emit()
        } catch {
            AppLogger.persistence.error("FetchedResultsController fetch failed: \(error.localizedDescription, privacy: .public)")
            continuation.yield([])
        }
    }

    func stop() {
        controller.delegate = nil
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        emit()
    }

    private func emit() {
        let tasks = (controller.fetchedObjects ?? []).map { $0.toDomain() }
        continuation.yield(tasks)
    }
}
