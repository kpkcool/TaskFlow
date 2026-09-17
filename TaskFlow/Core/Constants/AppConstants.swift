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

    /// Firestore collection used by the remote sync service.
    static let firestoreTasksCollection = "tasks"

    /// How often the SyncEngine retries failed operations automatically.
    static let syncRetryBaseDelaySeconds: UInt64 = 5
    static let syncRetryMaxAttempts = 5

    /// Minimum gap before a remote `updatedAt` counts as newer than the
    /// local one. Firestore `Timestamp` <-> `Date` conversion isn't
    /// bit-exact, so a task we just uploaded reads back a hair "newer" —
    /// without this tolerance that caused an endless pull/rewrite loop.
    static let syncTimestampToleranceSeconds: TimeInterval = 0.5
}
