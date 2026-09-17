//
//  FirebaseService.swift
//  TaskFlow
//
//  Owns Firebase bootstrap. Deliberately tolerant of a missing
//  GoogleService-Info.plist (or the SPM package not being added yet) so the
//  rest of the app — which is offline-first by design — never depends on
//  Firebase being configured to run.
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
            AppLogger.network.notice("GoogleService-Info.plist not found — running local-only. See README to enable Firestore sync.")
            return
        }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        isConfigured = true
        AppLogger.network.notice("Firebase configured.")
        #else
        AppLogger.network.notice("FirebaseCore package not linked — running local-only. See README to add the Firebase SPM package.")
        #endif
    }
}
