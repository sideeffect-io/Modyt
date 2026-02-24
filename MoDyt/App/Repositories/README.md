# Repositories Surface (Phase 1)

This folder defines the new repository surface, aligned with:

- Functional architecture (actor shell + pure policies)
- SOLID principles (small responsibilities and interface segregation)
- CLEAN architecture (domain + application repositories, no infrastructure leakage)
- Law of Demeter (callers consume narrow one-hop dependencies)

## Scope

Included:

- Devices
- Groups
- Scenes
- Unified favorites
- Tydom message router surface

Excluded in this phase:

- Areas
- Runtime wiring changes
- Replacing legacy `App/Datasources/*` implementations
- Repository unit tests (API still stabilizing)

## Layers

- `Domain/`: Pure models, shared `DomainType` and `DomainUpsert`, and pure policies.
- `Application/`: Generic SQLite repository actor, specialized factories/extensions, ingest DTOs.
- `Application/TydomRepositoryIngestMappers.swift`: anti-corruption boundary from `DeltaDoreClient` to repository DTOs.

## SQLite Backing

- Core actor:
  - `SQLiteDomainRepository<Item, Upsert>`
- Specialized repositories are created by factory functions on constrained extensions:
  - `DeviceRepository.makeDeviceRepository(...)`
  - `GroupRepository.makeGroupRepository(...)`
  - `SceneRepository.makeSceneRepository(...)`
- Group-specific extra behavior is provided through constrained extension methods:
  - `upsertMetadata(_:)`
  - `upsertMembership(_:)`
- SQLite table names:
  - `devices`
  - `groups`
  - `scenes`
- Domain models use a common `id` field as table primary key.
- Existing repository data is expected to be wiped manually before rollout (no schema migration logic in this phase).

## Observation Contract

- Observation continuation handling is centralized inside `SQLiteDomainRepository`.
- `observe*` APIs emit arrays only.
- `observe*` APIs emit an initial snapshot on subscription.
- `observeByID` emits either `[]` or `[item]`.
- `observeByIDs` emits found items only, in caller-requested order.
- Projected streams are deduplicated with `RepositoryStreamOperators.mapDistinct`.

## Contracts

- Device grouped projection remains available via `observeGroupedByType()` on device-specialized repository.
- IDs are `String` across all repository surfaces:
  - device ID: gateway `uniqueId` string
  - group ID: gateway `id` converted to decimal string at ingest boundary
  - scene ID: gateway `id` converted to decimal string at ingest boundary
- Repository domain payload fields use repository-owned `JSONValue`.
- `DeltaDoreClient` dependency is constrained to router/mapper boundary files.
- Cross-source favorites are sorted by:
  1. `dashboardOrder` ascending
  2. source priority (`device`, `scene`, `group`)
  3. `name` ascending
- New surface uses only `dashboardOrder` (no `favoriteOrder`).
- Favorites are composed from devices/groups/scenes (no dedicated favorites table).
- `FavoriteItem` has no standalone row identifier and includes `name`, `usage` (`Usage`), and `type`.

## Router Contract

`TydomMessageRepositoryRouter` routes and persists only:

- `.devices`
- `.groupMetadata`
- `.groups`
- `.scenarios`

All other message types are ignored in this phase.

## Adoption Plan

1. Keep legacy datasources intact.
2. Introduce adapters implementing these repositories.
3. Migrate call sites incrementally:
   - router
   - devices/groups/scenes features
   - dashboard favorites
