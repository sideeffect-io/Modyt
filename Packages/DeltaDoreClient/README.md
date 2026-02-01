# DeltaDoreClient

Swift package to connect to Delta Dore Tydom gateways, with explicit connection flows for
stored credentials and new cloud credentials.

## Quick start (flow-based)

```swift
import DeltaDoreClient

let client = DeltaDoreClient.live()
let flow = await client.inspectConnectionFlow()

switch flow {
case .connectWithStoredCredentials:
    let session = try await client.connectWithStoredCredentials(
        options: .init(mode: .auto)
    )
    let connection = session.connection

case .connectWithNewCredentials:
    let credentials = TydomConnection.CloudCredentials(
        email: "user@example.com",
        password: "secret"
    )
    let session = try await client.connectWithNewCredentials(
        options: .init(mode: .auto(cloudCredentials: credentials)),
        selectSiteIndex: { sites in
            // Present UI and return the chosen index.
            return 0
        }
    )
    let connection = session.connection
}
```

### Flow inspection

`inspectConnectionFlow()` only checks for persisted gateway credentials (MAC + password):

- If present: `.connectWithStoredCredentials`
- Otherwise: `.connectWithNewCredentials`

## Stored credentials flow

```swift
let session = try await client.connectWithStoredCredentials(
    options: .init(mode: .auto) // .forceLocal or .forceRemote also available
)
```

Behavior:
- Uses stored gateway credentials and cached local IP (if any).
- Attempts local connection first, then remote fallback.
- If remote fails, stored data is cleared and an error is returned.

## New credentials flow

```swift
let credentials = TydomConnection.CloudCredentials(
    email: "user@example.com",
    password: "secret"
)

let session = try await client.connectWithNewCredentials(
    options: .init(mode: .auto(cloudCredentials: credentials)),
    selectSiteIndex: { sites in
        // Provide a site selection when more than one site exists.
        return 0
    }
)
```

Force local with a known IP + MAC:

```swift
let session = try await client.connectWithNewCredentials(
    options: .init(mode: .forceLocal(
        cloudCredentials: credentials,
        localIP: "192.168.1.10",
        localMAC: "AA:BB:CC:DD:EE:FF"
    ))
)
```

Behavior:
- Uses cloud credentials to fetch sites and gateway password.
- If only one site exists, it is automatically selected.
- If multiple sites exist and no selector/index is provided, an error is returned.
- Attempts local connection first, then remote fallback.
- If remote fails, stored data is cleared and an error is returned.

## Listing sites

```swift
let sites = try await client.listSites(
    cloudCredentials: .init(email: "user@example.com", password: "secret")
)
```

## Storage behavior

- Stored data includes: gateway MAC + gateway credentials + cloud credentials.
- Selected site is not persisted.
- Stored data is cleared on explicit disconnect and when remote connection fails.

## Custom services and hosts

```swift
let client = DeltaDoreClient.live(
    credentialService: "io.sideeffect.deltadoreclient.gateway",
    gatewayMacService: "io.sideeffect.deltadoreclient.gateway-mac",
    cloudCredentialService: "io.sideeffect.deltadoreclient.cloud-credentials",
    remoteHost: "mediation.tydom.com"
)
```

## DeltaDoreCLI

```
DeltaDoreCLI --mode auto --cloud-email <email> --cloud-password <password> [--site-index <n>]
DeltaDoreCLI --mode stored
DeltaDoreCLI --mode new --cloud-email <email> --cloud-password <password> [--site-index <n>]

Options:
  --mode auto|stored|new       Connection flow (default: auto)
  --cloud-email <email>        Cloud account email
  --cloud-password <password>  Cloud account password
  --site-index <n>             Site index (skips prompt)
  --list-sites                 List available sites and exit (requires cloud login)
  --dump-sites-response        Print raw site list response and exit
  --force-local                Force local mode (stored/new flows)
  --force-remote               Force remote mode (stored/new flows)
  --local-ip <ip>              Local gateway IP (required with --force-local for new flow)
  --local-mac <mac>            Local gateway MAC (required with --force-local for new flow)
  --clear-storage              Clear stored data before running
  --help                       Show this help
```
