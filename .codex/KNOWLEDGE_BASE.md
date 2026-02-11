# MoDyt Knowledge Base (Session-Derived)

## 1) Mistakes To Avoid, Tips, And Self-Rules

### A. Process and Tooling Rules

- Rule: use `apply_patch` for manual file edits; do not issue patch blocks through `shell_command`.
- Rule: for app compile/run validation, use XcodeBuildMCP tools (`build_sim`, `build_run_sim`) rather than only package-level commands.
- Rule: after architecture/API changes, update docs (`README`/`.codex` docs) in the same change set.
- Rule: when asked for architecture refactors, keep edits minimal and behavior-preserving first, then style/UI pass.

### B. UI/State Management Mistakes To Avoid

- Rule: do not bind shutter target/pending UI directly to DB-backed actual value.
- Rule: separate actual state (source of truth from repository/DB) from target/pending state (user intent).
- Rule: send shutter command on interaction commit (release/tap), not continuously while sliding.
- Rule: actual layer must never teleport to target; it should converge as updates arrive.
- Rule: keep pending indicator visible only while there is a real in-flight divergence.
- Rule: avoid state mutation during view update cycles (no "Modifying state during view update" patterns).

### C. Architecture Hygiene Rules

- Rule: stores do not create other stores.
- Rule: store ownership belongs to the owning SwiftUI view.
- Rule: parent-child store communication goes through explicit closures passed in view composition.
- Rule: keep reducers pure (`State x Event -> State + Effects`), with side effects executed in effect handlers.
- Rule: inject dependencies via closures/capability structs, not concrete infrastructure types.
- Rule: split monolithic stores/factories into feature-scoped units.
- Rule: maintain one test file per store and keep store logic testable in isolation.

### D. Practical Tips

- Use `DeltaDoreClient` public connection flow APIs (`inspectConnectionFlow`, `connectWithStoredCredentials`, `connectWithNewCredentials`) from app stores/factories.
- Keep lifecycle wiring explicit: app active state forwarded from `scenePhase` to connection/session logic.
- Run both runtime app checks and package tests when touching cross-cutting behavior (`DeltaDoreClient`, `Persistence`, app stores).

---

## 2) Your Architectural Guidance (Codified)

### Functional + Composition-First

- Prefer functional architecture principles:
- immutable state models,
- pure reducers,
- explicit effects,
- composition over inheritance.

- Store/state machine naming pattern expectation:
- `State`, `Event`, `Effect`, `DelegateEvent`.

- Keep side effects at boundaries:
- domain/store reducer logic stays pure,
- IO/network/database operations live in injected effect closures.

### Dependency Injection Practices

Preferred DI order:
- closures first,
- capability structs wrapping closures second,
- protocols only at true external boundaries.

- Do not inject concrete infrastructure directly into feature stores when closures can express needed capability.
- Keep dependencies narrow and feature-specific (no "god dependency" object for every store).
- Factories are composition boundaries: build concrete closures there, not in reducers.

### Communication Between Layers

Expected direction:
- Views own stores.
- Stores expose state + `send(event)`.
- Child-to-parent signaling via closure callbacks/delegate events.
- Parent-to-child behavior via injected closures/dependencies.

- Avoid hidden shared mutable wiring; cross-layer communication should be explicit in constructors and view composition.

### Store Granularity and Responsibilities

You prefer fine-grained feature stores instead of one monolith:
- app/root route store,
- auth flow store,
- session/root-tab runtime boundary,
- dashboard list store,
- dashboard card store,
- shutter control store,
- devices list store,
- settings/disconnect store.

You explicitly asked for:
- dedicated files by feature/view/store,
- one store test file per store,
- high isolation and testability.

### UI and Data Semantics Guidance

- SQLite/repository is source of truth for device state.
- UI may use optimistic/pending state, but must reconcile with repository updates.
- Polling/lifecycle behavior should be tied to app active/background lifecycle (`setAppActive`).

---

## 3) Overall Architecture Of The App (Current Codebase)

### A. Top-Level Composition

- Entry point: `MoDyt/App/MoDytApp.swift`.
- Creates live `AppEnvironment`.
- Builds and injects individual factory values into SwiftUI `EnvironmentValues`.

### B. Routing and Flow

`AppRootStore` in `MoDyt/App/Features/AppRoot/Stores/AppRootStore.swift` owns:
- route (`authentication` vs `runtime`),
- app active flag.

`AppRootView` in `MoDyt/App/Features/AppRoot/Views/AppRootView.swift`:
- maps route to `AuthenticationRootView` or `RootTabView`,
- forwards `scenePhase` to root store as app-active event.

### C. Factory/DI Layer

- Per-feature factories in `MoDyt/App/Factories/*` create stores with closure dependencies.
- Environment keys expose each factory (`authenticationStoreFactory`, `rootTabStoreFactory`, etc.).
- `WithStoreView` initializes a store from a factory per owning view, matching your ownership rule.

### D. Feature Stores

`AuthenticationStore`:
- inspects connection flow,
- handles login/site selection/connect,
- emits authenticated delegate event.

`RootTabStore`:
- runtime session boundary for persistence bootstrap, message stream, refresh, app-active propagation, disconnect flow.

`DashboardStore`:
- observes favorites IDs,
- toggles/reorders favorites,
- requests refresh.

`DashboardDeviceCardStore`:
- observes a single device,
- applies optimistic updates for non-shutter controls,
- dispatches device commands.

`ShutterStore`:
- per-device shutter UI/control logic (`actualStep`, `targetStep`, in-flight),
- sends commit command via injected closure,
- syncs with `ShutterRepository` snapshots.

`DevicesStore`:
- observes all devices,
- derives grouped sections,
- toggles favorites and refresh.

`SettingsStore`:
- handles disconnect UI state and async disconnect request.

### E. Data Layer

`DeviceRepository` (`actor`):
- persists devices in SQLite via `Persistence` package DAO,
- applies incoming `TydomMessage`,
- exposes async streams (`observeDevices`, `observeFavorites`, `observeDevice`),
- handles favorite ordering/reordering and optimistic updates.

`ShutterRepository` (`actor`):
- persists shutter UI sync state in SQLite (`shutter_ui_state`),
- merges device stream into shutter snapshots,
- exposes `observeShutter`.

`AppEnvironment` bridges:
- `DeltaDoreClient`,
- repositories,
- command/refresh/disconnect closures,
- logging and utility functions.

### F. Message/Command Pipeline (Runtime)

- Connection/messages from `DeltaDoreClient`.
- `RootTabStore` decodes stream and applies messages to repository.
- Repositories update SQLite + push async stream updates.
- Feature stores consume streams and update view state.
- User intents dispatch commands via injected closures back through environment/client.

### G. Test Architecture

- Store-oriented test files under `MoDyt/MoDytTests` (`AuthenticationStoreTests`, `RootTabStoreTests`, `DashboardStoreTests`, etc.).
- Pattern aligns with your preference: isolated store testing with fake/injected closures.

---

## 4) Latest Session Updates (Dashboard Device Ownership Split)

### A. Dashboard Favorites Data Flow (Updated)

- `DashboardStore` should observe favorite **devices** (`[DeviceRecord]`) instead of only favorite IDs.
- `DashboardView` should pass the full `DeviceRecord` to each dashboard card; card identity/reorder still uses `uniqueId`.
- This removes the need for per-card generic device observation just to render name/type/status.

### B. Card Store Responsibility (Narrowed)

- `DashboardDeviceCardStore` is now favorite-only:
  - single intent: `favoriteTapped`,
  - single side effect: toggle favorite in repository.
- Control command dispatch (`applyOptimisticUpdate` / `sendDeviceCommand`) was removed from this store.
- Consequence: dashboard card store is now strictly "shared card chrome behavior", not device-control behavior.

### C. Device-Control Ownership by Type

- `ShutterView` / `ShutterStore` own shutter control and shutter-specific observation.
- `LightView` / `LightStore` own light control and light-specific observation.
- `DashboardDeviceCardView` routes control UI by `device.group`:
  - `.shutter` -> `ShutterView`,
  - `.light` -> `LightView`,
  - other groups -> no control widget.

### D. Why Shutter Observation Differs from Light Observation

- Shutter observation comes from `ShutterRepository.observeShutter`, which emits consolidated `ShutterSnapshot` values that include transient UI coordination state (`targetStep`, `originStep`, `ignoredEcho`) in addition to raw device data.
- Light observation can use `DeviceRepository.observeDevice` directly because current light UX does not require extra shutter-like reconciliation state.

### E. Xcode Project Sync Gotcha (Important)

- With file-system synchronized Xcode projects (`PBXFileSystemSynchronizedBuildFileExceptionSet`), replacing/recreating a test file can drop its membership exception entries.
- If that happens, the test file may be compiled into app target `MoDyt` and fail with:
  - `Compilation search paths unable to resolve module dependency: 'Testing'`,
  - warning that file is part of module `MoDyt`.
- Fix: re-add the test file path in both exception sets (`MoDytTests` target and `MoDyt` target exception list).

---

## 5) Latest Session Updates (AsyncSequence, Cross-Platform, Layout)

### A. Mistakes To Avoid

- Do not create passthrough `AsyncStream` wrappers (`Task` + `for await` + `yield`) just to cross actor boundaries when an async dependency closure can be awaited directly.
- Do not return non-Sendable async-sequence existentials from actor-isolated APIs to `@MainActor` call sites; use `any AsyncSequence<..., Never> & Sendable`.
- Do not apply `.toolbarBackground(..., for: .navigationBar/.tabBar)` or `.containerBackground(..., for: .navigation)` unguarded on macOS.
- Do not keep unused dependency closures and their matching `State`/`Event`/`Effect` plumbing once behavior is no longer used.

### B. Tips And Tricks

- Prefer dependency signatures like `() async -> ...` / `(String) async -> ...` for actor-isolated stream access; this avoids factory-level stream passthrough glue.
- For derived streams (`observeFavorites`, `observeDevice`), return `observeDevices().map { ... }` directly when no manual continuation management is needed.
- Encapsulate iOS-only chrome behavior in helper modifiers (for example `hideChromeBackgroundForMobileTabs()`), guarded with `#if os(iOS)`.
- For centered/balanced card controls on iPad, give each side equal flexible space (`.frame(maxWidth: .infinity, alignment: .center)`) rather than letting only one side expand.

### C. Architecture Patterns Reinforced

- Repository boundary owns continuation/observer lifecycle streams; higher-level derived streams should stay declarative (`map`) when possible.
- Store dependencies should expose capabilities (iterate async sequence, execute effect) rather than requiring concrete stream types.
- Dashboard root store scope should remain focused on favorites observation, reorder, and refresh; per-card favorite toggling belongs to card-level store.
- Cross-platform adaptation should be compile-time (`#if os(iOS)`) while preserving runtime behavior on iOS/iPadOS.

### D. Coding Preferences Captured

- You prefer aggressive dead-code cleanup: if a closure/effect/event path is unused, remove it entirely.
- You want platform fixes that preserve existing iOS and iPadOS behavior exactly.
- You value visually balanced controls on iPad (horizontally centered and evenly distributed), not just functionally correct layouts.

---

## 6) Latest Session Updates (Temperature Card + DeltaDore Sensor Semantics)

### A. Mistakes To Avoid

- Do not assume any numeric telemetry field is directly displayable temperature; `configTemp` can be a configuration code (e.g. `520`) and not ambient temperature.
- Do not use generic numeric fallback logic for thermo cards without excluding non-display keys (`config*`, `lightPower`, `jobsMP`, etc.).
- Do not display raw/unknown unit strings (e.g. `NA`) as temperature unit labels.
- Do not lock UI decisions too early; when UX direction changes (gauge vs no gauge), keep thermo view composition simple so controls can be removed without architecture churn.

### B. Tips And Tricks

- For DeltaDore thermo devices, prioritize `outTemperature` and known temperature keys before any generic value extraction.
- When validating unclear payload semantics, quickly compare with established integrations (`hass-deltadore-tydom-component`, `tydom2mqtt`) to confirm which field is used in practice.
- Normalize unit values before rendering (`degC` -> `°C`, `degF` -> `°F`) and drop invalid placeholders like `NA`.
- Use Swift `Text` numeric formatting for display consistency: `.number.precision(.fractionLength(1))` for one decimal digit.

### C. Architecture Patterns Reinforced

- Temperature follows the same feature pattern as other device types, with dedicated `TemperatureView`, `TemperatureStore`, and `TemperatureStoreFactory`, wired through app environment/factories and dashboard card routing by device group.
- The store observes live streams from `DeltaDoreClient`-fed repository data rather than snapshot polling from the view layer.
- Device-specific parsing belongs in device/domain mapping (`DeviceRecord`) so UI/store layers remain focused on presentation and flow.

### D. Coding Preferences Captured

- Thermo card UI should stay minimal and readable: no subtitle (`Thermo`) and no gauge in the current direction.
- Temperature value should be the visual focal point: centered horizontally in the card, shown with one decimal digit, with unit when valid.

---

## 7) Latest Session Updates (Shutter/Light Concurrency + Runtime Cleanup)

### A. Mistakes To Avoid

- Do not use `updatedAt` as a proxy for meaningful shutter change in reconciliation logic; unrelated gateway/device updates can change timestamps and create false positives.
- Do not register observers asynchronously inside an `AsyncStream` builder (`Task { addObserver }`) without synchronous registration first; termination can happen first and leave orphan observers.
- Do not add buffering/stacking/time-window hacks to hide state collisions when semantic dedup and proper stream boundaries can solve the root cause.
- Do not let `syncDevices` grow with ad-hoc branches; treat size/branch explosion as a design smell early.

### B. Tips And Tricks

- For observer-based streams, use `AsyncStream.makeStream()`, register observer synchronously, then start async snapshot loading in a cancellable task.
- Always cancel in-flight initial snapshot tasks in `onTermination` and remove observer in all exit paths (failure + termination).
- Deduplicate per-device streams with semantic comparison of meaningful control fields (`kind`, `key`, `range`, mapped `ShutterStep`), not metadata/timestamp noise.
- Reproduce optimistic UI race bugs with integration tests that interleave:
    - pending shutter target,
    - shutter echo to target,
    - unrelated light updates,
    - stale shutter payload,
    - final real shutter movement.

### C. Architecture Patterns Reinforced

- Keep `DeviceRepository` as raw persisted source of truth and `ShutterRepository` as domain-specific projection layer that merges raw state with shutter UI intent state.
- Ensure `ShutterRepository` maintains a single long-lived upstream device observation (`deviceObservationTask` guard) per repository instance; shutter stores consume per-device projected streams.
- Keep dashboard-level observation focused on lightweight device identity/ordering data; control-specific state belongs to per-device control streams.
- Prefer semantic dedup at stream boundaries over temporal heuristics in view/store state.

### D. Coding Preferences Captured

- You prefer simple, deterministic state models over defensive complexity.
- You explicitly prefer dedup-based isolation between controls and want to avoid time-based gating mechanisms.
- You want failed mitigation experiments removed quickly when they do not solve root cause.
- You want stronger integration tests before/with fixes when concurrency bugs are hard to reproduce.
- You want code-smell driven cleanup (function size, unused wiring/deps/events/effects/tests), as shown by the `RootTabStore` simplification request.

---

## 8) Latest Session Updates (Light Gauge Jerkiness + Glass Rendering)

### A. Root Cause Findings

- The main visible jank on light gauge on/off transitions was dominated by card compositing cost, not only gauge math.
- Disabling `.glassCard(cornerRadius: 22)` on dashboard cards immediately made gauge animation smooth, confirming the rendering bottleneck.
- Co-locating gauge animation and switch visual state changes in the same glass-rendered card increases invalidation pressure and frame drops.

### B. UI/Animation Lessons

- Simplifying `LightView` structure helps update isolation:
  - keep gauge animation state local (`GaugeControlView`),
  - keep parent state minimal (`requestedPowerTarget`),
  - avoid broad state fan-out from card container updates.
- A `Path`/`Shape`-based gauge (`PathGauge` + `GaugeArc`) is a good tradeoff for predictable animation and lower view-tree complexity.
- For diagnosing jerky SwiftUI animations, A/B toggles are high-signal:
  - remove card glass,
  - move switch out of card,
  - remove switch visual animations,
  - then reintroduce effects one by one.

### C. Glass Strategy That Preserved Performance

- Replacing native card glass effect with a faux glass recipe based on material (`.ultraThinMaterial`/`.thinMaterial`) reduced animation jank significantly.
- A unified modifier API is kept through `glassCard(..., tone:)` with two tones:
  - `surface` for outer card,
  - `inset` for nested control card.
- Final visual tuning guidance:
  - keep both modes flat/homogeneous (no visible gradient bias),
  - keep outer light cards brighter/whiter than background,
  - keep inset light cards darker than outer card to preserve hierarchy,
  - use slight light-mode shadow only for depth (avoid halo blur).

### D. Swift Concurrency Guidance Reinforced

- `Task.detached` should remain a last resort; prefer structured concurrency and actor isolation.
- In this codebase snapshot, no `Task.detached` usage is present.
- To avoid blocking the main thread without detached tasks:
  - keep heavy IO/compute in actor/repository boundaries,
  - expose async APIs and streams to stores,
  - confine UI state mutation to main-actor contexts only.

### E. Product/Team Preference Captured

- You prioritize smooth interaction and frame stability over perfect visual parity with native glass APIs.
- You prefer iterative visual calibration with screenshot-based comparison until parity is close enough.

---

## 9) Latest Session Updates (Thermostat Card Scope + Store Init Cleanup)

### A. Mistakes To Avoid (And How To Avoid Them)

- Do not keep feature wiring for capabilities the device does not support (for thermostat here: setpoint write commands).
- Avoid this by validating capability scope early and then removing unused code across all impacted layers (view, store, factory, repository/environment wiring, tests).
- Do not leave production call sites noisy with explicit `nil` arguments when initializer defaults can express intent.
- Avoid this by defaulting optional bootstrap parameters (`initialDevice`) to `nil` in store inits and keeping factories minimal.
- Do not leave card UI empty while wiring evolves; keep at least stable read-only telemetry visible.
- Avoid this by prioritizing read path first (temperature/humidity observation), then layering controls only after backend capability confirmation.

### B. Tips, Tricks, And Useful Commands

- Fast audit for noisy `nil` call sites:
  - `rg --line-number "initialDevice:\\s*nil" MoDyt/App`
- Fast audit for stores that can adopt defaulted bootstrap args:
  - `rg --line-number "initialDevice:\\s*DeviceRecord\\?" MoDyt/App/Features/Dashboard`
- Verify targeted edits quickly with focused diffs:
  - `git diff -- <files...>`
- Validate signature and wiring changes with simulator build:
  - XcodeBuildMCP `build_sim` for scheme `MoDyt`.

### C. Architectural Patterns And Best Practices Reinforced

- Keep feature architecture consistent by device type: dedicated view + store + factory, wired through environment dependencies.
- Keep store dependencies capability-based and minimal: read-only devices should expose observation-only dependencies.
- Treat software layers explicitly:
  - UI layer: present telemetry and user intents only.
  - Store layer: observation/state mapping and intent orchestration.
  - Factory/environment layer: concrete dependency composition.
  - Repository/client layer: source-of-truth data and protocol operations.
- When requirements change, prefer full-path cleanup over partial deactivation to preserve clarity and testability.

### D. Coding Preferences Captured

- You prefer pragmatic scope correction over speculative features (read-only thermostat is acceptable and preferred when command support is absent).
- You want architecture symmetry with existing features, but not at the cost of dead/unusable control paths.
- You prefer cleaner production composition code (omit explicit `nil` where defaults make call sites clearer).
- You expect “remove unused wiring” to include all relevant layers, not only the visible UI.
