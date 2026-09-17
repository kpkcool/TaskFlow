//
//  AppLogger.swift
//  TaskFlow
//

import Foundation
import os

enum AppLogger {
    static let persistence = Logger(subsystem: "com.kpkcool.TaskFlow", category: "persistence")
    static let sync = Logger(subsystem: "com.kpkcool.TaskFlow", category: "sync")
    static let network = Logger(subsystem: "com.kpkcool.TaskFlow", category: "network")
    static let ui = Logger(subsystem: "com.kpkcool.TaskFlow", category: "ui")
}
