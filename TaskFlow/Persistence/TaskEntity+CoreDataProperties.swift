//
//  TaskEntity+CoreDataProperties.swift
//  TaskFlow
//

import CoreData
import Foundation

extension TaskEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<TaskEntity> {
        NSFetchRequest<TaskEntity>(entityName: "TaskEntity")
    }

    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var taskDescription: String
    @NSManaged public var status: String
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var sortOrder: Double
    @NSManaged public var syncStatus: String
    @NSManaged public var isDeletedPendingSync: Bool

}

extension TaskEntity: Identifiable {
}
