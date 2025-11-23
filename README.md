# TableGlass

TableGlass is an open-source database management tool.
Designed for macOS. Built using SwiftUI. It aims to be lightweight and easy to use. Compatible with databases such as PostgreSQL, MySQL and Sqlite3.

## Features

- **Multi-Database Support**: Planned support for PostgreSQL, MySQL, and Sqlite3 databases.
- **Intuitive UI**: An easy-to-use interface makes database management easy.
- **Open Source**: The source code is available on GitHub, and community contributions are welcome.

## SSH Tunneling

- Enable SSH tunneling per connection from the Connection Management window.
- Host aliases are parsed directly from `~/.ssh/config`; use standard `Host` entries without wildcards for best results.
- Pick a Keychain identity from the SSH section when enabling tunneling; the app stores only a persistent reference, never the raw key material.
- TableGlass never stores private keys or passwords in plain text. SSH identities are resolved through the macOS Keychain using persistent references.
- To exercise real tunnel establishment, launch the app with the `LocalDebug` build configuration. CI and unit tests rely on mocked tunnel, Keychain, and SSH config providers to avoid touching local environments.
- Recommended local setup:
  1. Add the remote target to `~/.ssh/config` with a unique `Host` alias.
  2. Ensure the corresponding identity is stored in the login Keychain.
  3. Grant TableGlass access to the identity the first time the tunnel runs.

## Testing & Mocks

- CI and UI/unit tests run against the mock database layer in `TableGlassKit/Database` to avoid live connections.
- Use `MockDatabaseConnection` and `MockDatabaseQueryExecutor` to script metadata responses, query results, errors, and per-call latency; register SQL routes via `MockDatabaseQueryRoute`.
- Use `MockDatabaseTableDataService` to seed table rows and configure per-table behaviors (delays, rejection of specific IDs) when exercising grid edits.
- Extend mocks by adding new routes/behaviors rather than hand-rolling per-test stubs so new cases inherit logging and failure simulation.
- Real database or tunnel-backed tests must be gated behind the `LocalDebug` configuration; CI should never talk to live databases.

### Local PostgreSQL testing (LocalDebug only)

The `LocalDebug` build configuration is pre-configured to use a real PostgreSQL connection via `PostgresNIO`.

- **Dependency**: The `postgres-nio` SwiftPM dependency is automatically linked to the `TableGlassKit` framework. The application uses this driver when launched under the `LocalDebug` configuration.
- **Authentication**: Store your local database password in the macOS Keychain as a generic password. The application will read it using the identifier specified in the `TABLEGLASS_POSTGRES_PASSWORD_ID` environment variable. The `KeychainDatabasePasswordResolver` handles this securely, and your password is never logged or stored directly.
- **Environment**: Before running the app or integration tests locally with the `LocalDebug` scheme, set the following environment variables:
  - `TABLEGLASS_POSTGRES_HOST`
  - `TABLEGLASS_POSTGRES_PORT` (default: `5432`)
  - `TABLEGLASS_POSTGRES_USER`
  - `TABLEGLASS_POSTGRES_DB`
  - `TABLEGLASS_POSTGRES_SCHEMA` (default: `public`)
  - `TABLEGLASS_POSTGRES_PASSWORD_ID` (the "Account" name of the generic password in Keychain)
- **Execution**: To run the `LocalDebug`-only integration tests, select the `TableGlass` scheme and run the test action (or `xcodebuild test -scheme TableGlass -configuration LocalDebug -testPlan TableGlass -destination 'platform=macOS' -only-testing:TableGlassTests/PostgresNIOIntegrationTests/testCrudAndMetadataRoundTrip`). These tests are guarded by `#if LOCALDEBUG && canImport(PostgresNIO)` and will only execute under the correct configuration. The `TableGlassTests/TableGlass.xctestplan` carries default local env vars; override as needed in your shell.
- **Timeouts**: Postgres connection and query calls now fail fast (10s handshake, 30s per query) to avoid hanging test runs when PostgreSQL isn’t reachable.

## Architecture Overview

- `TableGlassKit`: Swift framework providing shared business logic and database abstractions.
  - `Connections`: handles saved profiles and retrieval stores used by the UI layer.
  - `Database`: defines async/await protocols for connections and transactions.
    Schema metadata models live here.
    Placeholder factories for PostgresNIO/MySQLNIO/sqlite3 stay until driver integrations land.
- `TableGlass`: SwiftUI app target that renders the UI and injects `TableGlassKit` services.

## Development

This section outlines how to set up your development environment to contribute to TableGlass.

### Prerequisites

Install the following tools (Homebrew examples shown):

- **SwiftLint**: `brew install swiftlint`
- **swift-format**: `brew install swift-format`
- **Xcode 16+**: required for `xcodebuild` and running the app/tests.

### One-shot workflow (lint, format check, tests, docs)

Run all project checks locally (what CI will run):

```sh
./scripts/dev-check.sh
```

This verifies SwiftLint, swift-format lint, the `TableGlass` scheme tests, and regenerates HTML docs under `docs/` (gitignored).

### Building and Testing

- **Build the project:**
  ```sh
  xcodebuild build -scheme TableGlass -destination 'platform=macOS'
  ```
- **Run unit and UI tests:**
  ```sh
  xcodebuild test -scheme TableGlass -destination 'platform=macOS'
  ```
  The project is Xcode-based, so `swift test` is not currently available.

### Linting and Formatting

This project uses SwiftLint and swift-format to maintain a consistent code style.

- **Lint check:**
  ```sh
  swiftlint lint
  ```
- **Auto-correct lint issues where possible:**
  ```sh
  swiftlint --fix
  ```
- **Format check (no writes):**
  ```sh
  swift-format lint -r TableGlass TableGlassKit TableGlassTests TableGlassUITests
  ```
- **Apply formatting in place:**
  ```sh
  swift-format format -i -r TableGlass TableGlassKit TableGlassTests TableGlassUITests
  ```

#### Xcode Build Phase Integration (Recommended)

To get real-time feedback in Xcode, add build phases that run these tools:

1. In the Xcode Project Navigator, select the `TableGlass` project.
2. Select the `TableGlass` target and navigate to the `Build Phases` tab.
3. Click the `+` icon and select `New Run Script Phase`.
4. Add a phase for SwiftLint and another for swift-format before the `Compile Sources` phase.

**SwiftLint Run Script:**

```sh
export PATH="$PATH:/opt/homebrew/bin"

if which swiftlint > /dev/null; then
  swiftlint
else
  echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
fi
```

**swift-format Check Run Script:**

This script will fail the build if formatting is incorrect, but it will not modify files.

```sh
export PATH="$PATH:/opt/homebrew/bin"

if which swift-format > /dev/null; then
  swift-format lint -r TableGlass TableGlassKit TableGlassTests TableGlassUITests
else
  echo "warning: swift-format not installed, download from https://github.com/apple/swift-format"
fi
```
