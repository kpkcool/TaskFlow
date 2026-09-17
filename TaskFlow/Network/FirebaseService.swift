//
//  FirebaseService.swift
//  TaskFlow
//
//  Owns Firebase bootstrap. Deliberately tolerant of missing Firebase
//  configuration so the offline-first app can still launch and keep local
//  changes pending instead of crashing.
//

import Foundation
import os

#if canImport(FirebaseCore)
import FirebaseCore
#endif

enum FirebaseService {

    /// True once `FirebaseApp.configure()` has run successfully. Everything
    /// upstream (Repository, SyncEngine) already treats "Firebase not
    /// configured" the same as "no network" — it just keeps tasks pending.
    private(set) static var isConfigured = false

    static func configureIfPossible() {
        #if canImport(FirebaseCore)
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            AppLogger.network.notice("GoogleService-Info.plist not found — running local-only.")
            return
        }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        isConfigured = true
        AppLogger.network.notice("Firebase configured.")
        #else
        AppLogger.network.notice("FirebaseCore package not linked — running local-only.")
        #endif
    }
}
