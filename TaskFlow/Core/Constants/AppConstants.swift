//
//  AppConstants.swift
//  TaskFlow
//

import Foundation

enum AppConstants {
    /// Gap left between newly appended tasks so future inserts rarely need
    /// to touch neighboring rows. See `SortOrderCalculator`.
    static let sortOrderStep: Double = 1000

    /// If two neighboring sortOrder values get closer than this, the section
    /// is renormalized on next reorder to keep floating point math sane.
    static let sortOrderMinGap: Double = 0.001

    // TODO: Prav — Change this for different Firestore collection name.
    static let firestoreTasksCollection = "tasks"

    /// How often the SyncEngine retries failed operations automatically.
    static let syncRetryBaseDelaySeconds: UInt64 = 5
    static let syncRetryMaxAttempts = 5
}
