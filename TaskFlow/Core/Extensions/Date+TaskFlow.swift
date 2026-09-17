//
//  Date+TaskFlow.swift
//  TaskFlow
//

import Foundation

extension Date {
    /// e.g. "10:42 AM" for today, "Sep 12" for older dates. Used by the
    /// debug screen and sync indicator.
    var shortSyncTimeString: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(self) {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: self)
    }
}
