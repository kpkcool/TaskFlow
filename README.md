# TaskFlow

Offline-first iOS task management board built with **Swift + UIKit**, using **MVVM-C + Repository Pattern**.

## Features

- Three-column Kanban board: **To Do, In Progress, Done**
- Create, edit, delete, reorder, and move tasks
- Drag & drop and swipe actions
- Offline-first local persistence with **Core Data**
- Automatic sync with **Firebase Firestore**
- Last-updated-wins conflict resolution
- Sync status and offline indicators
- Pull-to-refresh and Debug screen
- Unit tests for repository, sync, view model, and Core Data

## Architecture

```text
UIKit ViewControllers
        ↓
ViewModels
        ↓
TaskRepository
      ↙   ↘
 Core Data  Firestore
      ↘   ↙
    SyncEngine
```

**Rules**
- Core Data is the local source of truth.
- ViewControllers/ViewModels never access Firebase directly.
- All reads and writes go through the Repository.
- User action → Core Data → UI update → Firebase sync.

## Requirements

- **Xcode 26.3+**
- **iOS 26.2+**
- Firebase Swift Package dependencies
- `GoogleService-Info.plist` included in the app target

## Getting Started

```bash
git clone <repo-url>
cd TaskFlow
open TaskFlow.xcodeproj
```

Select an iOS Simulator and press **⌘R**.

The app works locally without Firebase. When Firebase is available, pending changes sync automatically.

## Firebase Setup

The project already contains the Firebase dependencies and `GoogleService-Info.plist`.

To use another Firebase project:

1. Create/add an iOS app in Firebase.
2. Use bundle ID: `com.kpkcool.TaskFlow`
3. Download `GoogleService-Info.plist`.
4. Replace the existing file and ensure it is included in the `TaskFlow` target.
5. Create a Firestore database with a `tasks` collection.

## Build & Test

```bash
xcodebuild -project TaskFlow.xcodeproj \
  -scheme TaskFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build
```

Run tests:

```bash
xcodebuild -project TaskFlow.xcodeproj \
  -scheme TaskFlow \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug \
  test
```

Or use **⌘U** in Xcode.

## Data & Sync

Tasks are stored locally in Core Data and synced to Firestore.

```text
User Action
    ↓
ViewModel
    ↓
Repository
    ↓
Core Data
    ↓
UI Update
    ↓
Firebase Sync
```

Failed operations remain pending and are retried with exponential backoff. Sync is also retried when connectivity returns, the app becomes active, or the user manually triggers sync.

### Conflict Resolution

**Last Updated Wins** using `updatedAt`:

- Local newer → keep local and upload.
- Remote newer → update local data.
- Synced local task missing remotely → remove locally.
- Pending local task missing remotely → keep locally.

### Reordering

Tasks use gap-based `sortOrder` values (step `1000`). Sections are renormalized when gaps become too small.

## Project Structure

```text
TaskFlow/
├── App/
├── Core/
├── Models/
├── Persistence/
├── Network/
├── Repository/
├── Sync/
├── Features/
│   ├── TaskBoard/
│   ├── TaskEditor/
│   └── Debug/
├── AppDelegate.swift
├── SceneDelegate.swift
└── Resources/
```

## Testing

Unit tests cover:

- Repository CRUD, validation, move and reorder
- Sync and retry behavior
- Conflict resolution
- ViewModel state and grouping
- Core Data persistence

Tests use mock services and do not require a real Firebase backend.

## Notes

- Firestore collection: `tasks`
