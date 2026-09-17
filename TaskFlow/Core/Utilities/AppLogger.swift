//
//  AppLogger.swift
//  TaskFlow
//

import Foundation
import os

enum AppLogger {
    static let persistence = Logger(subsystem: "com.example.com.TaskFlow", category: "persistence")
    static let sync = Logger(subsystem: "com.example.com.TaskFlow", category: "sync")
    static let network = Logger(subsystem: "com.example.com.TaskFlow", category: "network")
    static let ui = Logger(subsystem: "com.example.com.TaskFlow", category: "ui")
}
