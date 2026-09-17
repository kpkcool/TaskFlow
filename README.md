# TaskFlow — Offline-First Task Board

A production-quality iOS task management board built with **Swift + UIKit**, following **MVVM-C + Repository Pattern** with an **offline-first** design.

## Features

- **Three-column Kanban board** — To Do, In Progress, Done
- **CRUD** — Create, edit, delete tasks with validation
- **Drag & drop** — Reorder within a section or move between sections
- **Context menu** — Long-press for Edit / Move to… / Delete
- **Offline-first** — Every mutation saves to Core Data immediately; UI never waits on the network
- **Automatic sync** — Pending changes upload to Firebase Firestore when connectivity returns
- **Conflict resolution** — Last-updated-wins (compare `updatedAt` timestamps)
- **Sync status indicators** — Per-task badges (✓ synced / ⏳ pending / ⚠ failed) and a nav-bar icon
- **Offline banner** — "You're offline. Changes will sync when you're back online."
- **Pull-to-refresh** — Manual sync trigger
- **Developer/Debug screen** — Network state, pending count, last sync time, Simulate Offline toggle, Sync Now, Clear Local Data
- **Core Data persistence** — Tasks survive app quit and relaunch
- **Unit tests** — 25 tests covering Repository, SyncEngine, ViewModel, and Core Data persistence

## Architecture

```
UIKit ViewControllers
        ↓
    ViewModels (async/await + @Published)
        ↓
    TaskRepository (protocol — only dependency VMs know)
      ↙         ↘
Core Data      Firestore
 (LOCAL)       (REMOTE)
      ↘         ↙
     SyncEngine
```

**Key rules:**
- Core Data is the **local source of truth**
- Firebase is never accessed from ViewControllers or ViewModels
- All reads/writes go through the Repository
- **User action → Core Data first → UI update → Firebase sync** (never the reverse)

### Folder Structure

```
TaskFlow/
├── App/                    # Coordinator protocol, AppCoordinator
├── Core/
│   ├── Constants/          # AppConstants
│   ├── Errors/             # TaskRepositoryError
│   ├── Extensions/         # UIView+Layout, Date+TaskFlow
│   ├── Utilities/          # SortOrderCalculator, AppLogger
│   └── AppDependencies.swift  # Composition root / DI container
├── Models/                 # Task, TaskStatus, SyncStatus, SyncState, TaskSection
├── Persistence/            # CoreDataStack, TaskEntity (hand-written), CoreDataTaskStore
├── Network/                # NetworkMonitor, FirebaseService, FirestoreTaskService
├── Repository/             # TaskRepository protocol, TaskRepositoryImpl
├── Sync/                   # SyncEngine, SyncOperation, SyncQueue
├── Features/
│   ├── TaskBoard/          # Board VC, ViewModel, Coordinator, TaskCell, SectionHeader
│   ├── TaskEditor/         # Editor VC, ViewModel, Coordinator
│   └── Debug/              # DebugViewController
├── AppDelegate.swift
├── SceneDelegate.swift
└── Resources/
    ├── Assets.xcassets
    └── LaunchScreen.storyboard
```

## Requirements

- **Xcode 26.3+** (Swift 5)
- **iOS 26.2+** deployment target
- No third-party dependencies required for local-only mode

## Getting Started

### 1. Clone and open

```bash
git clone <repo-url>
cd TaskFlow
open TaskFlow.xcodeproj
```

### 2. Build and run (works immediately — no Firebase needed)

The app runs fully offline out of the box. All task CRUD, drag-and-drop, reordering, and Core Data persistence work without any Firebase setup. Tasks will show an orange sync badge (⚠) because the Firestore stub always reports "network unavailable" — this is expected.

Select a simulator (e.g. iPhone 17 Pro) and press **⌘R**.

### 3. Enable Firebase Firestore sync (optional)

> **See the detailed TODO comments in `FirebaseService.swift` for step-by-step instructions.**

**Step 1 — Add Firebase SPM package:**
1. In Xcode: **File → Add Package Dependencies…**
2. Enter URL: `https://github.com/firebase/firebase-ios-sdk`
3. Set dependency rule to **Up to Next Major Version** (e.g. `11.0.0`)
4. Select products: **FirebaseCore**, **FirebaseFirestore**
5. Add to target: **TaskFlow**

**Step 2 — Add GoogleService-Info.plist:**
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Create a project (or use an existing one)
3. Add an iOS app with bundle ID: `com.example.com.TaskFlow`
4. Download the generated `GoogleService-Info.plist`
5. Drag it into the `TaskFlow/` group in Xcode (check "Copy items if needed", add to target TaskFlow)

**Step 3 — Create Firestore database:**
1. In Firebase Console → **Firestore Database → Create Database**
2. Choose **"Start in test mode"** for development
3. Select a region close to you
4. The app will auto-create a `tasks` collection on first sync

**Step 4 — Rebuild.** The `#if canImport(FirebaseFirestore)` guards automatically activate the real Firestore implementation. No code changes needed.

### 4. Run tests

```bash
# Unit tests only (skip UI tests which need a stable simulator)
xcodebuild -project TaskFlow.xcodeproj \
  -scheme TaskFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  -skip-testing:TaskFlowUITests \
  test
```

Or in Xcode: **⌘U** (Product → Test).

## Offline-First Write Strategy

Every user mutation follows this exact sequence:

```
User Action
    ↓
ViewModel
    ↓
Repository
    ↓
Save to Core Data immediately (syncStatus = pendingCreate/pendingUpdate/pendingDelete)
    ↓
Update UI immediately (from Core Data observation)
    ↓
Check Network
    ↓
Online?   →  YES → Firebase upload → mark .synced
          →  NO  → Keep pending (retry on reconnect / app-foreground / manual sync)
```

The user **never** waits for Firebase before seeing their change.

## Conflict Resolution

**Strategy: Last Updated Wins**

When the SyncEngine pulls remote changes and finds a task that also has local pending edits:

| Condition | Action |
|-----------|--------|
| `local.updatedAt > remote.updatedAt` | Keep local, re-upload to Firebase |
| `remote.updatedAt > local.updatedAt` | Overwrite Core Data with remote copy |
| Task is `.synced` locally but missing remotely | Treat as remote delete — remove locally |
| Task is pending locally but missing remotely | Keep local — it hasn't been uploaded yet |

This is a deliberately simple, deterministic strategy suitable for a single-user or small-team board.

## Retry Strategy

- Failed sync operations are marked `.failed` (data is **never** lost)
- Automatic retry with exponential backoff (base 5s, max 5 attempts)
- Retry also triggers on:
  - Network connectivity restored
  - App becomes active (foreground)
  - User taps the sync icon or pulls to refresh
  - User taps "Sync Now" in the Debug screen

## Data Model

```swift
struct Task {
    let id: UUID
    var title: String
    var taskDescription: String
    var status: TaskStatus        // .todo | .inProgress | .done
    let createdAt: Date
    var updatedAt: Date
    var sortOrder: Double
    var syncStatus: SyncStatus    // .synced | .pendingCreate | .pendingUpdate | .pendingDelete | .failed
}
```

Core Data entity: `TaskEntity` (hand-written, `codeGenerationType = none`)

Firestore collection: `tasks/{taskId}` — stores `id`, `title`, `description`, `status`, `createdAt`, `updatedAt`, `sortOrder`.

## Reordering Strategy

Uses a **gap-based sortOrder** (step = 1000) so reordering a single task only writes that one row:

```
Task A = 1000
Task B = 2000
Task C = 3000

Move C between A and B → C.sortOrder = 1500
```

When gaps get too small (`< 0.001`), the entire section is renormalized with clean spacing.

## Unit Tests

| Suite | Tests | Covers |
|-------|-------|--------|
| `TaskRepositoryTests` | 11 | Create, update, delete, move, reorder, validation, offline session |
| `SyncEngineTests` | 8 | Pending sync, failure handling, retry, conflict resolution (both directions), remote delete |
| `TaskBoardViewModelTests` | 4 | Section grouping/sorting, sync state, error propagation, delete delegation |
| `CoreDataPersistenceTests` | 2 | Tasks survive quit+relaunch, pending changes survive for later sync |

All tests use mock protocols (`MockTaskStore`, `MockFirestoreTaskService`, `MockTaskRepository`) — no real Firebase or persistent Core Data involved.

## What's Pending (TODO: Prav)

Search the codebase for `TODO: Prav` to find all spots requiring manual action:

| File | What to do |
|------|------------|
| `FirebaseService.swift` | 3-step Firebase integration guide (SPM package + plist + Firestore DB) |
| `FirestoreTaskService.swift` | Stub explanation — auto-resolves once Firebase is added |
| `AppDelegate.swift` | Note that `configureIfPossible()` is a no-op until Firebase is wired |
| `AppConstants.swift` | Optional: change Firestore collection name |

**No code changes are needed** — just the Xcode package addition + GoogleService-Info.plist file.

## Bundle ID

The current bundle ID is `com.example.com.TaskFlow`. If you change it, make sure the Firebase Console iOS app uses the same bundle ID, or `GoogleService-Info.plist` won't match and Firebase will silently fail to configure.
