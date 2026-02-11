# MoDyt Knowledge Base (Concise)

This is the condensed, non-duplicative engineering memory for the project.

## 1) Non-Negotiable Rules

- Use `apply_patch` for manual edits.
- Use XcodeBuildMCP (`build_sim`, `test_sim`, `build_run_sim`) for app validation.
- Keep behavior-preserving changes first; do style/UI refinement after behavior is correct.
- Update docs when architecture/API contracts change.
- Never hide side effects in reducers; reducers remain pure (`State x Event -> State + Effects`).
- Stores do not create other stores.
- Store ownership belongs to the owning SwiftUI view (`WithStoreView` + factory).
- Parent/child coordination uses explicit closures, not hidden shared mutable wiring.
- Remove dead code aggressively (unused dependencies/events/effects/tests/wiring).

## 2) Architecture Snapshot

### App Composition

- `MoDyt/App/MoDytApp.swift` creates `AppEnvironment` and injects feature factories via `EnvironmentValues`.
- Factories are composition boundaries; they build concrete closure dependencies.

### Core Layers

- UI: SwiftUI views + intents only.
- Store: state mapping and orchestration (`@Observable @MainActor`).
- Factory/Environment: dependency composition.
- Repository/Client: source-of-truth and IO.

### Data Source of Truth

- Repositories backed by SQLite are authoritative:
  - `DeviceRepository` for device snapshots/favorites.
  - `ShutterRepository` for shutter projection + UI intent reconciliation.
- UI optimistic state may exist, but must reconcile against repository streams.

## 3) Preferred Patterns

### Functional + DI

- Functional core / imperative shell.
- DI priority: closures first, capability structs second, protocols at external boundaries only.
- Keep dependencies narrow and feature-scoped.

### Store Pattern

- Store state is minimal and testable.
- Async observation/effects run in inner `Worker` actor.
- Expose dependencies as async capabilities, e.g.:
  - `@Sendable (String) async -> any AsyncSequence<..., Never> & Sendable`

### Device Card Slice Pattern (for new card types)

1. Add descriptor parsing/normalization in `DeviceRecord`.
2. Include descriptor in `ObservationSignature` and `FavoritesSignature`.
3. Update `DeviceRepository.dashboardGroup(for:)` inference for unknown usages.
4. Add `View` + `Store` + `StoreFactory`.
5. Wire factory in `MoDytApp` environment.
6. Route rendering in `DashboardDeviceCardView`.
7. Add dedicated store tests.

## 4) Domain Semantics and Pitfalls

### Classification and Routing

- `DashboardStore` observes favorite descriptions; per-device control ownership belongs to device feature stores.
- `DashboardDeviceCardStore` is favorite-toggle behavior only; control logic lives in feature stores.

### Sensor Data Semantics

- Do not treat all numeric values as display telemetry.
- Temperature:
  - prefer explicit temperature keys (for example `outTemperature`).
  - ignore config-like values (`configTemp`, etc.) for UI temperature.
  - normalize units (`degC` -> `deg C`, `degF` -> `deg F`) and ignore invalid placeholders (`NA`).
- Sunlight:
  - metadata ranges can be wrong; use fixed domain range `0...1400 W/m2`.
  - normalize units in descriptor mapping (`kW/m2` to `W/m2`).

### Shutter/Light Coordination

- Shutter UI must separate actual vs target/pending state.
- Shutter command should be sent on commit, not continuously during drag.
- Do not use `updatedAt` timestamp as semantic control-change signal.

## 5) Concurrency and Stream Rules

- Prefer structured concurrency; avoid `Task.detached` unless truly necessary.
- Avoid passthrough `AsyncStream` wrappers when a direct async dependency closure is enough.
- For observer streams:
  - register observer synchronously,
  - start snapshot loading in cancellable task,
  - always clean up observer/task on termination.
- Deduplicate streams by semantic signatures (meaningful fields), not timestamps/noise.

## 6) UI and Performance Rules

- Dashboard cards are fixed-height; keep controls compact and intrinsic.
- Centering for all devices/orientations:
  - make cluster intrinsic (`.fixedSize(horizontal: true, vertical: false)`),
  - then center with `.frame(maxWidth: .infinity, alignment: .center)`.
- On iPad, avoid asymmetric expansion that drifts content; balance spacing/alignment explicitly.
- Heavy glass compositing can hurt animation smoothness; validate with A/B checks and prefer simpler rendering when needed.
- Preserve existing iOS behavior when applying iPad/macOS fixes.

## 7) Testing and Validation

- One test file per store, focused and isolated.
- Add tests whenever descriptor semantics or routing logic change.
- Prefer targeted runs for touched areas (`-only-testing`).
- Always report validation limitations explicitly when sandbox/simulator/tooling blocks full verification.

### Xcode File-System Sync Gotcha

- Adding/replacing test files can break target membership exceptions.
- If `Testing` module errors appear in app target, fix `PBXFileSystemSynchronizedBuildFileExceptionSet` entries in `project.pbxproj`.

## 8) Useful Commands

- Fast code search:
  - `rg -n "pattern" MoDyt -g '*.swift'`
  - `rg --files`
- Scope check:
  - `git status --short`
  - `git diff -- <paths...>`
- Xcode project sync diagnostics:
  - `rg -n "PBXFileSystemSynchronizedBuildFileExceptionSet|MoDytTests/" MoDyt.xcodeproj/project.pbxproj`
- Targeted test examples:
  - `test_sim` with `-only-testing:MoDytTests/<SuiteName>`

## 9) Coding Preferences (Captured)

- Functional architecture and composition-first design.
- Consistent feature symmetry: `View` + `Store` + `StoreFactory`.
- Minimal blast radius changes and fast iterative refinements.
- Pixel-level UI consistency, especially iPad alignment/centering.
- Practical correctness over uncertain metadata assumptions.
- Prefer deterministic behavior and semantic dedup over heuristic/time-window hacks.
- Optimize for smooth interactions and responsive animations.
