# Tydom Frame Gap Report (2026-02-22)

## Scope

- Source capture: `/Users/thibaultwittemberg/Desktop/frame_types.txt`
- Snapshot date: 2026-02-22
- Goal: baseline current parser/decoder behavior before lossless remediation

## Frame Inventory

- Total websocket frame blocks: 25
- Unique uriOrigin values: 16

| uriOrigin | count | methods | statuses | bodyless |
|---|---:|---|---|---:|
| `/areas/data` | 1 | `HTTP/1.1` | `200` | 0 |
| `/configs/file` | 1 | `HTTP/1.1` | `200` | 0 |
| `/devices/1757536200/endpoints/1757536200/data` | 1 | `HTTP/1.1` | `200` | 0 |
| `/devices/1757536792/endpoints/1757536792/data` | 2 | `HTTP/1.1` | `200` | 1 |
| `/devices/1757587577/endpoints/1757587577/data` | 1 | `HTTP/1.1` | `200` | 0 |
| `/devices/1757599581/endpoints/1757599581/data` | 1 | `HTTP/1.1` | `200` | 0 |
| `/devices/1757603034/endpoints/1757603034/data` | 1 | `HTTP/1.1` | `200` | 0 |
| `/devices/1767200810/endpoints/1767200810/data` | 2 | `HTTP/1.1` | `200` | 1 |
| `/devices/1767201013/endpoints/1767201013/data` | 1 | `HTTP/1.1` | `200` | 0 |
| `/devices/1767201143/endpoints/1767201143/data` | 1 | `HTTP/1.1` | `200` | 0 |
| `/devices/data` | 8 | `HTTP/1.1,PUT` | `200` | 0 |
| `/groups/file` | 1 | `HTTP/1.1` | `200` | 0 |
| `/info` | 1 | `HTTP/1.1` | `200` | 0 |
| `/moments/file` | 1 | `HTTP/1.1` | `200` | 0 |
| `/refresh/all` | 1 | `HTTP/1.1` | `200` | 1 |
| `/scenarios/file` | 1 | `HTTP/1.1` | `200` | 0 |

## Current Mapping vs Expected

- Mapping here reflects current code behavior before implementation changes.

- areas: 1 frame(s)
- deviceUpdates -> devices if cache info exists else raw: 16 frame(s)
- gatewayInfo: 1 frame(s)
- groupMetadata + cacheMutations: 1 frame(s)
- groups: 1 frame(s)
- moments (currently empty for key mom): 1 frame(s)
- none->raw message: 3 frame(s)
- scenarios: 1 frame(s)

## Loss Points

- Bodyless ACK frames not typed: 3 frame(s) have HTTP status and routing headers but decode to .none -> .raw. (Packages/DeltaDoreClient/Sources/DeltaDoreClient/TydomMessages/TydomMessageDecoder.swift:37)
- /moments/file key mismatch: Captured payload uses key `mom`; decoder expects `moments`, producing empty typed moments. (Packages/DeltaDoreClient/Sources/DeltaDoreClient/TydomMessages/TydomMessageDecoder.swift:491)
- Device data null entries dropped: 4 null value entries observed (/devices/data:thermicLevel, /devices/data:shutterCmd, /devices/1767200810/endpoints/1767200810/data:thermicLevel, /devices/1767201013/endpoints/1767201013/data:shutterCmd); current extraction requires non-nil value. (Packages/DeltaDoreClient/Sources/DeltaDoreClient/TydomMessages/TydomMessageDecoder.swift:177)
- /configs/file partial projection: Top-level keys include 13 keys; decoder projects ['endpoints', 'groups', 'scenarios'] and leaves 10 keys only in raw payload. (Packages/DeltaDoreClient/Sources/DeltaDoreClient/TydomMessages/TydomMessageDecoder.swift:48)
- Hydrator drops updates without cache device info: When device info is missing for a uniqueId, update is skipped and can collapse to .raw when all are skipped. (Packages/DeltaDoreClient/Sources/DeltaDoreClient/TydomMessages/TydomMessageHydrator.swift:99)

## Prioritized Remediation Checklist

- P0: Add typed ACK decoding for bodyless HTTP responses with uriOrigin/transactionId/status/headers.
- P0: Introduce unified message metadata carrying raw frame, body bytes, and decoded body JSON for every emitted message.
- P0: Preserve null device entry values and entry-level payload metadata in typed device messages.
- P1: Accept both `moments` and `mom` keys for `/moments/file` while preserving full payload JSON.
- P1: Keep `/configs/file` full top-level payload recoverable in typed output metadata.
- P1: Preserve decoded metadata even when hydrator cannot resolve device info (avoid information loss).
- P2: Add fixture-driven regression suite from redacted capture and enforce lossless invariants in CI.

