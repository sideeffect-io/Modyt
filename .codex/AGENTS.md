# Agents Overview — Swift Home Automation Application

This repository implements an iOS/iPadOS/macOS application for controlling a DeltaDore box using a functional programming architecture and strong testability guarantees.  
Agents working with this repo (AI assistants, automation tools, or new team members) should understand:

- Functional design principles (immutability, pure functions, higher order functions, side effects, composition)
- How we structure side effects via dependency injection
- SOLID principles applied in a Swift + functional programming context
- Testability via injecting functions and capabilities
- Our Git workflow (linear history, feature branches, fast-forward merges)

> This high-level overview provides context. Read the doc and find detailed procedural steps and examples through dedicated **Agent Skills**.

---

## Structure

- The project is an Xcode project with one production target `MoDyt` and one unit tests target `MoDytTests`.
- All the local dependencies are Swift Packages in the `Packages` folder.
- The Swift Package `Packages/DeltaDoreClient` should be used to interface with the home automation box. Read the `Packages/DeltaDoreClient/README.md` file for more context about it.
- The Swift Package `Packages/Persistence` should be used when you need to persist data in a database like SQLite. Read the `Packages/Persistence/README.md` file for more context about it.

---

## Plan

For long reasoning operations and complex tasks we do an execution plan upfront and ask for validation.
When executing the plan, you can use parallel tasks/sub-agents to optimize the execution and ask sub-agents to challenge themselves and the main agent.

---

## Functional Architecture Philosophy

**North Star**  
We partition code into:

1. **Inert Domain** — immutable data (`struct`/`enum`), no side effects  
2. **Pure Computations** — deterministic pure functions (input → output)  
3. **Actions/Effects** — side effects (network, hardware, IO) at the edges

**Key Concepts**  
- Immutability by default  
- Pure functions everywhere possible  
- Composition over inheritance  
- Higher-order functions and partial application (or curry when this apply)
- Lazy/thunked dependencies for expensive resources

We apply SOLID in a Swift FP context:

- **S**ingle Responsibility: small functions that performs one thing, narrow types
- **O**pen/Closed: extend via composition, not inheritance (when possible)
- **L**iskov: injected functions uphold contracts
- **I**nterface Segregation: tiny capability structs or functions, not fat protocols
- **D**ependency Inversion: domain depends on capabilities, not implementations

These emphasize modularity without unnecessary abstractions.

This aligns with modern functional design patterns that emphasize clarity, testability, and correctness.

- Use Enums as a namespace for related free functions.
- A function should be max 30 lines of code, split it otherwise (use composition).
- A file should be max 300 lines of code, split it otherwise (use composition and extensions).
- When working in a swift package, types visibility is important, by default types should not be visible from the outside (internal), a type should be public only if it is part of the public API used by the end client.

---

## Testability Patterns

We favor **function injection instead of object mocking**:

- Capability structs of closures (e.g., network client, clock, logger)
- Use of higher order function
- Inject only what a unit needs (small slices)
- Pure core logic that can be tested with no environment dependencies
- We focus on unit tests (not integration tests).
- Always use the Swift Testing framework and use the Given, When, Then pattern

---

## Git Workflow Summary

We use the Git CLI.

We adopt a **GitHub Flow** style:

- One long-lived `main` branch
- Short-lived feature/fix branches
- Frequent rebasing from `main`
- Fast-forward merges only
- Destructive operations are forbidden unless explicit (reset --hard, clean, restore, rm, …)

This yields a clean, linear history and makes `git bisect` and blame more effective.

--

## How to run and test

In the context of a Swift package, we use the Swift CLI with commands like `swift build` or `swift test`
If this is a full Xcode project, we can use the XCodeBuildMCP server.

--

## Swift documentation

When needed use the Cupertino MCP server to access the officiel Swift documentation and Apple coding guides.

---

## Lessons Learned

- Shutter UI: build with a dual-layer track (background + foreground) and invert values when the visual direction is reversed; keep mask/handle/progress indicator in the same coordinate space to avoid drift.
- Devices list: keep a consistent row layout with SF Symbol icon treatment and spacing; support dark mode and subtle texture rather than flat white backgrounds.
- DeltaDore discovery: use `/ping` then stop on first success; normalize MAC addresses; avoid Bonjour; close the connection after probing.
- Connection resolution: keep a fast-path for an already-known working connection before running full discovery.
- Logging: add message-pipeline logs that include the config file path and `devices-meta` details for supportability.
- Tooling: use XcodeBuildMCP for full Xcode project builds/tests; reserve `swift build`/`swift test` for Swift packages.
- Guard iOS-only SwiftUI modifiers (like `.textInputAutocapitalization`) with `#if os(iOS)` to keep macOS builds compiling (see `MoDyt/App/Views/LoginView.swift`).
- Use the existing `glassCard(...)` modifier from `MoDyt/App/Views/Components/Components.swift` for card-like surfaces to keep UI consistency.
- Prefer the `DeltaDoreClient` connection flows (`inspectConnectionFlow`, `connectWithStoredCredentials`, `connectWithNewCredentials`) instead of rolling ad-hoc gateway logic in app code.
- When writing custom SQL with `Packages/Persistence`, always use parameter bindings (`?`) to avoid injection and keep queries consistent with the DAO patterns.
- For tests or alternate storage, build DAOs from closures (in-memory `DAO`) rather than mocking SQLite directly.
- Reuse preferred patterns in packages: keep types `internal` by default and make them `public` only when part of the external API.
- After CLI changes, a quick sanity check is `swift run DeltaDoreCLI --help` before attempting live connections.
- For cloud site/gateway lookup, normalize MAC addresses (strip separators, uppercase) and retry variants; keep the original MAC for websocket usage.
- Swift Testing `#expect(throws:)` requires the error type to conform to `Equatable`; add conformance or use a different assertion style.
- Avoid returning non-Sendable `AsyncSequence` from actor-isolated APIs; expose `AsyncStream` instead to keep concurrency-safe boundaries.
- Keep CLI code in a functional-core/imperative-shell shape: minimal `@main`, parsing/IO orchestration split into small files.
- Prefer `rg --files` / `rg -n` for discovery, then `nl -ba` + `sed -n` to inspect Swift files with line numbers.
- Run package tests with `swift test --package-path Packages/DeltaDoreClient` and `swift test --package-path Packages/Persistence` before app-level changes.
- Use `xcodebuild -list -project MoDyt.xcodeproj` to confirm schemes before invoking `xcodebuild -scheme MoDyt -project MoDyt.xcodeproj`.
- Keep UI flows split by domain (`MoDyt/App/Authentication` and `MoDyt/App/Runtime`) with dedicated stores and views.
- Centralize route switching in `AppCoordinatorStore` (`@Observable`, `@MainActor`) and surface navigation via delegate events.
- Keep reducers pure and push derived collections (grouped devices, favorites) into helper functions.
- Rule: when moving SwiftUI views between folders, update Xcode project references and create target folders before moving files.
- Rule: keep `@Bindable` store types aligned with view ownership (avoid mismatching `AppStore` vs `AuthenticationStore` in login views).

