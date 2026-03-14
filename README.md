# MoDyt

MoDyt is a SwiftUI app for browsing and controlling a Delta Dore Tydom installation from a modern, dashboard-first interface.

The project focuses on three things:

- a fast favorite-based dashboard for the controls you actually use
- a local-first data layer that keeps gateway data cached in SQLite
- a feature architecture built around pure state machines, thin stores, and explicit effect executors

## Overview

MoDyt connects to a Tydom gateway, loads devices, groups, and scenes, then projects the most useful controls into a customizable dashboard.

From the current codebase, the app supports:

- authentication with stored credentials or new cloud credentials
- site selection when a Tydom account exposes multiple sites
- local or remote connection flows through the bundled `DeltaDoreClient`
- device browsing by category
- group browsing
- scene browsing and execution
- favorite pinning and drag-and-drop reordering on the dashboard
- dedicated cards for shutters, lights, thermostats, heat pumps, temperature sensors, sunlight sensors, smoke detectors, and energy consumption
- persistent local caching for devices, groups, scenes, and favorite order

## Tech Stack

- Swift 6
- SwiftUI
- Observation (`@Observable`)
- Swift Concurrency (`async/await`, actors, `AsyncSequence`)
- Swift Testing (`import Testing`)
- SQLite via a local `Persistence` Swift package
- Xcode project with local Swift packages in `Packages/`

## Repository Layout

```text
.
├── MoDyt/                   # App target
│   └── App/
│       ├── App/             # App entry point and dependency injection
│       ├── Features/        # Feature views, stores, reducers, effect executors
│       ├── Navigation/      # App root and main tab navigation
│       ├── Repositories/    # Domain repositories and message routing
│       ├── StoreTools/      # Shared runtime helpers for stores
│       └── UIComponents/    # Reusable SwiftUI components
├── MoDytTests/              # App tests using Swift Testing
└── Packages/
    ├── DeltaDoreClient/     # Tydom connection, auth, protocol decoding, CLI
    ├── Persistence/         # SQLite-backed DAO layer
    └── Regulate/            # Throttle/debounce utilities used by the UI
```

## How It Was Built

MoDyt is structured as a SwiftUI shell on top of a small functional architecture.

Each feature follows the same pattern:

- immutable `State`
- `Event` values representing user actions or external inputs
- `Effect` values describing side effects
- a pure `StateMachine.reduce(_:_:) -> Transition<State, Effect>`
- an `@Observable @MainActor` store that applies transitions and launches effects
- one dedicated effect executor per workflow
- a factory in the composition root that assembles the feature with concrete dependencies

That pattern is visible across the app in features such as authentication, dashboard, devices, groups, scenes, and settings.

### App composition

`MoDytApp` boots the application by creating `AppCompositionRoot.live()` and injecting store factories into the SwiftUI environment. `AppRootView` decides between two high-level routes:

- authentication flow
- connected runtime

Once authenticated, `MainView` hosts the app shell with five tabs:

- Dashboard
- Devices
- Groups
- Scenes
- Settings

### Data flow

The live gateway integration is isolated in the local `DeltaDoreClient` package.

At runtime, gateway messages are decoded into typed Tydom models, then passed to `TydomMessageRepositoryRouter`, which persists them into local repositories for:

- devices
- groups
- scenes
- acknowledgements

The UI does not render directly from raw gateway payloads. Instead, feature stores observe repository snapshots and project them into view state. Favorites are treated as a projection over devices, groups, and scenes, which makes dashboard composition and reordering straightforward.

### Persistence

The local `Persistence` package provides a small SQLite DAO layer built around:

- `SQLiteDatabase` as the actor owning the SQLite connection
- `TableSchema` to describe row mapping
- `DAO` for CRUD and queries

MoDyt stores its cache under Application Support in a SQLite database (`tydom.sqlite.v2`). Repositories merge incoming gateway payloads into persisted domain models instead of treating the UI as a direct transport client.

### UI approach

The app is fully written in SwiftUI and uses custom visual building blocks rather than default list-heavy screens. The codebase includes:

- adaptive layouts for compact and wide size classes
- glass-style cards and custom color tokens
- orientation-aware login and settings screens
- dashboard cards specialized by control type

### Testing strategy

The repository has a large Swift Testing suite covering:

- pure reducer/state machine transitions
- store side effects
- repository behavior
- favorites projection and ordering
- Delta Dore protocol and connection flows

This is why the architecture keeps reducers pure and pushes IO behind executors and repositories: it makes the interesting behavior cheap to test.

## Local Packages

### `DeltaDoreClient`

Encapsulates Tydom authentication and connectivity:

- inspect stored-vs-new credential flow
- fetch sites from cloud credentials
- connect locally or remotely
- decode gateway messages
- expose a CLI for protocol/debug workflows

### `Persistence`

Provides the SQLite-backed storage layer used by repositories for devices, groups, and scenes.

### `Regulate`

Provides lightweight debounce/throttle primitives and SwiftUI helpers for time-based interaction control.

## Getting Started

### Requirements

- a recent Xcode version with Swift 6 support
- the iOS SDK matching the current project configuration
- a Delta Dore Tydom account and gateway to exercise the live flows

The current Xcode project is configured for:

- scheme: `MoDyt`
- bundle identifier: `io.sideeffect.MoDyt`
- Swift version: `6.0`
- iOS deployment target: `26.2`

### Open the project

```bash
open MoDyt.xcodeproj
```

The app target already references the local packages under `Packages/`, so there is no extra dependency bootstrap step.

### Build and run

In Xcode:

1. Open `MoDyt.xcodeproj`
2. Select the `MoDyt` scheme
3. Choose an iPhone or iPad simulator compatible with the deployment target
4. Run the app

From the command line, a typical build command looks like this:

```bash
xcodebuild \
  -project MoDyt.xcodeproj \
  -scheme MoDyt \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2" \
  build
```

If that simulator is not installed on your machine, replace the destination with one that exists locally.

### Run tests

```bash
xcodebuild \
  -project MoDyt.xcodeproj \
  -scheme MoDyt \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2" \
  test
```

## Why This Structure

This repository intentionally separates concerns:

- connection and protocol logic live in a dedicated package
- repositories own cached source-of-truth data
- feature stores stay small
- reducers remain deterministic
- side effects are explicit and replaceable

That combination makes the app easier to evolve as more device types, gateway flows, and dashboard behaviors are added.
