# MoDyt Agent Guide

MoDyt is an Apple-platform home automation app for Delta Dore gateways.

The repository contains:
- an Xcode app project with the `MoDyt` scheme
- local Swift packages in `Packages/`
- a Swift Testing test target in `MoDytTests`

This file should stay stable and structural. Put volatile implementation learnings in `.codex/KNOWLEDGE_BASE.md`, and remove stale entries when they no longer match the code.

## Read Order For A Fresh Session

1. Read `.codex/KNOWLEDGE_BASE.md`.
2. Read `MoDyt/App/App/MoDytApp.swift`.
3. Read `MoDyt/App/App/DI/AppCompositionRoot.swift`.
4. Read `MoDyt/App/App/DI/DependencyBag.swift`.
5. Read `MoDyt/App/Navigation/AppRoot/Views/AppRootView.swift`.
6. Read `MoDyt/App/Navigation/MainView/Views/MainView.swift`.
7. Then move to the feature or package directly related to the task.

## Project Map

### App Boot And Composition

- `MoDyt/App/App/MoDytApp.swift`
  - app entry point
  - creates `AppCompositionRoot.live()`
- `MoDyt/App/App/DI/`
  - app-level dependency composition
  - `DependencyBag` owns concrete live dependencies
  - `*StoreFactory` types build stores from narrow capabilities
  - `EnvironmentValues` entries expose factories to views

### Navigation Shell

- `MoDyt/App/Navigation/AppRoot/`
  - top-level route between authentication and runtime
- `MoDyt/App/Navigation/MainView/`
  - authenticated shell
  - tab container, gateway lifecycle handling, disconnect propagation

### Features

- `MoDyt/App/Features/<Feature>/`
  - most features are split into `Views/` and `Stores/`
  - some features also have `Models/` or `Projectors/`
- Dashboard slices live under `MoDyt/App/Features/Dashboard/`
  - card container: shared dashboard card shell and favorite toggling
  - device-specific slices: `Light`, `Shutter`, `HeatPump`, `Thermostat`, `Temperature`, `Sunlight`, `Smoke`, `EnergyConsumption`, `SceneExecution`

### Shared App Code

- `MoDyt/App/Models/`
  - shared domain models used across features and repositories
- `MoDyt/App/Repositories/`
  - source-of-truth and IO-facing repository layer
  - includes gateway-message ingestion via `TydomMessageRepositoryRouter`
- `MoDyt/App/StoreTools/`
  - `StartableStore`, `Transition`, async task helpers
- `MoDyt/App/UIComponents/`
  - reusable SwiftUI building blocks
  - `WithStoreView` owns store lifetime and calls `start()` once
- `MoDyt/App/Extensions/`
  - focused cross-cutting extensions and async helpers

### Tests

- `MoDytTests/`
  - app tests use Swift Testing
  - prefer one focused file per store, projector, or repository behavior

### Local Packages

- `Packages/DeltaDoreClient`
  - Delta Dore connection flows, gateway commands, decoded message stream, CLI
- `Packages/Persistence`
  - SQLite-backed generic DAO and table schema layer
- `Packages/Regulate`
  - debounce/throttle utilities used by the app

## Runtime Architecture

### Boot Flow

- `MoDytApp` creates the composition root.
- `AppRootView` routes to:
  - `AuthenticationRootView` before authentication
  - `MainView` after authentication
- `MainView` owns the tab shell and forwards app lifecycle changes to `MainStore`.

### Dependency Composition

- Live dependencies are assembled in `DependencyBag`.
- `AppCompositionRoot` turns the bag into feature factories.
- Views read factories from `EnvironmentValues`.
- Views create stores through `WithStoreView`.
- Stores do not create other stores.

### Store Pattern

Store shape is intentionally consistent:
- `State`
- `Event`
- `Effect`
- nested `StateMachine.reduce(...)`
- injected effect executors or narrow capability structs
- `send(_:)` mutates state through the reducer, then handles effects

Rules:
- reducers stay pure
- side effects happen only in effect handling
- prefer closures first, capability structs second, protocols only at external boundaries
- long-lived or authoritative state belongs in repositories, not views

### Repository And Gateway Flow

- `MainStoreDI.swift` builds `MainRuntime`, which is responsible for:
  - starting repositories
  - starting the gateway message stream
  - sending the initial gateway bootstrap requests
  - reconnect and disconnect orchestration
- `TydomMessageRepositoryRouter` converts decoded gateway messages into repository updates.
- `DeviceRepository`, `GroupRepository`, and `SceneRepository` persist app data through `Persistence`.

## How To Route A Change

### UI-Only Change

- Start in the relevant `Views/` folder.
- Check `UIComponents/` before creating a new shared component.
- Preserve current visual language unless the task explicitly changes design direction.

### Feature Behavior Change

- Read the feature `Store` first.
- Then read the matching DI file in `MoDyt/App/App/DI/`.
- Then inspect the view that owns the store.

### Gateway Or Message Handling Change

- Start in:
  - `MoDyt/App/App/DI/MainStoreDI.swift`
  - `MoDyt/App/Repositories/TydomMessageRepositoryRouter.swift`
  - `Packages/DeltaDoreClient`

### Persistence Or Source-Of-Truth Change

- Start in `MoDyt/App/Repositories/`.
- Touch `Packages/Persistence` only when the generic SQLite layer itself must change.

### New Dashboard Card Type

1. Add normalized device-specific parsing in a focused dashboard store helper, usually a `Device+...` file under `MoDyt/App/Features/Dashboard/<Feature>/Stores/`.
2. Add the feature `Store`.
3. Add the feature `View`.
4. Add the factory wiring in `MoDyt/App/App/DI/`.
5. Inject the factory through `AppCompositionRoot`.
6. Route the card in `DashboardDeviceCardView`.
7. Add dedicated tests in `MoDytTests`.

## Coding Guidance

- Favor functional core / imperative shell.
- Prefer composition over inheritance.
- Keep dependencies narrow and feature-scoped.
- Use enums as namespaces for related pure helpers when a namespace is useful.
- Aim for small functions and small files.
  - guideline: function around 30 lines max
  - guideline: file around 300 lines max
- In Swift packages, keep visibility `internal` by default and make types `public` only when part of the package API.
- Prefer minimal blast radius changes over wide refactors unless the task explicitly requires restructuring.
- Remove dead wiring when you touch an area.

## Testing Guidance

- Use Swift Testing for app tests.
- Prefer Given / When / Then structure.
- Add or update tests whenever reducer logic, effect routing, descriptor parsing, or repository semantics change.
- Prefer targeted validation while iterating, then broaden if needed.

## Validation

### App

- Prefer XcodeBuildMCP for app validation.
- Project: `MoDyt.xcodeproj`
- Main app scheme: `MoDyt`
- Other available schemes: `DeltaDoreCLI`, `DeltaDoreClient`, `Persistence`, `Regulate`

### Packages

- For package-local work, use Swift CLI from the package directory:
  - `swift build`
  - `swift test`

## Skills To Prefer When Relevant

- `swift-functional-architecture`
- `swift-concurrency`
- `swift-testing-expert`
- `swiftui-expert`
- `mobile-ios-design`
- `git-user`
- `security-threat-model`

If this guide and the code disagree, trust the code, then update this guide or the knowledge base so the next session starts from the correct model.
