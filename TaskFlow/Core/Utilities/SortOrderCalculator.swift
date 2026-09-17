//
//  SortOrderCalculator.swift
//  TaskFlow
//
//  Centralizes the "gap" sortOrder strategy so reordering a task only ever
//  rewrites that single task, not the whole section.
//

import Foundation

enum SortOrderCalculator {

    /// sortOrder for a brand-new task appended to the end of a section.
    static func appending(after lastSortOrder: Double?) -> Double {
        (lastSortOrder ?? 0) + AppConstants.sortOrderStep
    }

    /// sortOrder for a task moved/dropped between two existing tasks.
    /// Pass `nil` for `before` when dropping at the very top, and `nil` for
    /// `after` when dropping at the very bottom.
    static func between(before: Double?, after: Double?) -> Double {
        switch (before, after) {
        case (nil, nil):
            return AppConstants.sortOrderStep
        case (nil, .some(let after)):
            return after - AppConstants.sortOrderStep
        case (.some(let before), nil):
            return before + AppConstants.sortOrderStep
        case (.some(let before), .some(let after)):
            return (before + after) / 2
        }
    }

    /// True once two neighbors are so close that another insert between them
    /// would lose precision. Callers should renormalize the section when this
    /// happens.
    static func needsNormalization(before: Double?, after: Double?) -> Bool {
        guard let before, let after else { return false }
        return abs(after - before) < AppConstants.sortOrderMinGap
    }

    /// Recomputes clean, evenly-spaced sortOrder values (step, 2*step, ...)
    /// for an already-ordered list of tasks.
    static func normalized(_ tasks: [Task]) -> [Task] {
        tasks.enumerated().map { index, task in
            var updated = task
            updated.sortOrder = Double(index + 1) * AppConstants.sortOrderStep
            return updated
        }
    }
}
