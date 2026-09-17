# TaskFlow — Offline-First Task Board

A production-quality iOS task management board built with **Swift + UIKit**, following **MVVM-C + Repository Pattern** with an **offline-first** design.

## Features

- **Three-column Kanban board** — To Do, In Progress, Done
- **CRUD** — Create, edit, delete tasks with validation
- **Drag & drop** — Reorder within a section or move between sections
- **Context menu** — Long-press for Edit / Move to… / Delete
- **Swipe actions** — Swipe left to delete, swipe right to move status with a custom status picker
- **Offline-first** — Every mutation saves to Core Data immediately; UI never waits on the network
- **Automatic sync** — Pending changes upload to Firebase Firestore when connectivity returns
- **Conflict resolution** — Last-updated-wins (compare `updatedAt` timestamps)
- **Sync status indicators** — Per-task badges (✓ synced / ⏳ pending / ⚠ failed) and a nav-bar icon
- **Offline banner** — "You're offline. Changes will sync when you're back online."
- **Pull-to-refresh** — Manual sync trigger
- **Developer/Debug screen** — Network state, pending count, last sync time, Simulate Offline toggle, Sync Now, Clear Local Data
- **Core Data persistence** — Tasks survive app quit and relaunch
- **Unit tests** — Repository, SyncEngine, ViewModel, and Core Data persistence coverage

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
- Firebase Swift Package dependencies are already added to the Xcode project
- `GoogleService-Info.plist` is included in the app target for Firestore setup

## Getting Started

### 1. Clone and open

```bash
git clone <repo-url>
cd TaskFlow
open TaskFlow.xcodeproj
```

### 2. Build and run

Select an available simulator, such as **iPhone 17**, and press **⌘R**.

The app is offline-first: task creation, editing, deleting, dragging, reordering, and Core Data persistence work even when the network or Firebase is unavailable. When Firebase config succeeds, pending changes sync to Firestore automatically.

### 3. Firebase Firestore

Firebase dependencies and `GoogleService-Info.plist` are present. To use a different Firebase project:

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Create a project (or use an existing one)
3. Add an iOS app with bundle ID: `com.kpkcool.TaskFlow`
4. Download the generated `GoogleService-Info.plist`
5. Replace the existing `TaskFlow/GoogleService-Info.plist` and make sure it is included in the `TaskFlow` target

Create a Firestore database in Firebase Console. For development, "Start in test mode" is fine; the app writes to the `tasks` collection.

### 4. Build From Terminal

```bash
xcodebuild -project TaskFlow.xcodeproj \
  -scheme TaskFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

### 5. Run tests

```bash
xcodebuild -project TaskFlow.xcodeproj \
  -scheme TaskFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug \
  test
```

Or in Xcode: **⌘U** (Product → Test).

## What Is Working

- App launches through `AppDelegate` and configures Firebase before Firestore is touched.
- Core Data is the local source of truth for all visible tasks.
- Create task works with title validation and automatic sort ordering.
- Edit task works and marks synced tasks for update.
- Delete task works from context menu and swipe action.
- Drag and drop works for reordering within a column and moving between columns.
- Swipe-left delete opens a confirmation alert and resets the card if cancelled.
- Swipe-right status move opens the custom centered `MoveStatusSheetController`.
- Context menus support edit, move, and delete.
- Pull-to-refresh triggers a sync attempt.
- Sync status is shown at task level and in the navigation bar.
- Offline state is surfaced with an app banner.
- Debug screen can simulate offline mode, force sync, show pending count, show last sync, and clear local data.
- Firestore sync path is wired through `FirestoreTaskService` when Firebase config succeeds.
- Local-only fallback is safe: if Firebase is unavailable, the app keeps changes locally as pending instead of crashing.
- Retry/backoff is handled by `SyncEngine` and `SyncQueue`.
- Unit coverage exists for repository writes, sync behavior, view model grouping/state, and Core Data persistence.

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
| `TaskRepositoryTests` | 12 | Create, update, delete, move, reorder, validation, offline session |
| `SyncEngineTests` | 9 | Pending sync, failure handling, retry, conflict resolution (both directions), remote delete |
| `TaskBoardViewModelTests` | 4 | Section grouping/sorting, sync state, error propagation, delete delegation |
| `CoreDataPersistenceTests` | 2 | Tasks survive quit+relaunch, pending changes survive for later sync |

All tests use mock protocols (`MockTaskStore`, `MockFirestoreTaskService`, `MockTaskRepository`) — no real Firebase or persistent Core Data involved.

## Current Notes

- The app target bundle ID is `com.kpkcool.TaskFlow`.
- Firestore collection name is `tasks` in `AppConstants.firestoreTasksCollection`.
- UI tests are still the default Xcode template and should be expanded before relying on them for release confidence.
- Firestore security rules should be reviewed before production use.

## Bundle ID

The current app bundle ID is `com.kpkcool.TaskFlow`. If you change it, make sure the Firebase Console iOS app uses the same bundle ID, or `GoogleService-Info.plist` will not match the app.
