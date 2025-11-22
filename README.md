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

You will need the following tools installed. The easiest way to install them is via [Homebrew](https://brew.sh/).

- **SwiftLint**: For enforcing Swift style and conventions.
  ```sh
  brew install swiftlint
  ```
- **SwiftFormat**: For formatting Swift code.
  ```sh
  brew install swift-format
  ```
- **swift-doc**: For generating API documentation.
  ```sh
  brew install swift-doc
  ```

### Building and Testing

You can build and run tests from the command line using `xcodebuild`.

- **Build the project:**
  ```sh
  xcodebuild build -scheme TableGlass -destination 'platform=macOS'
  ```
- **Run unit and UI tests:**
  ```sh
  xcodebuild test -scheme TableGlass -destination 'platform=macOS'
  ```

### Linting and Formatting

This project uses SwiftLint and SwiftFormat to maintain a consistent code style.

#### Manual Formatting

To format the codebase manually, run the following command from the project root:

```sh
swift-format -i -r .
```

To automatically correct linting issues where possible:

```sh
swiftlint --fix
```

#### Xcode Build Phase Integration (Recommended)

To get real-time feedback in Xcode, it is recommended to add build phases that run these tools.

1.  In the Xcode Project Navigator, select the `TableGlass` project.
2.  Select the `TableGlass` target and navigate to the `Build Phases` tab.
3.  Click the `+` icon and select `New Run Script Phase`.
4.  Add a phase for SwiftLint and another for SwiftFormat before the `Compile Sources` phase.

**SwiftLint Run Script:**

```sh
export PATH="$PATH:/opt/homebrew/bin"

if which swiftlint > /dev/null; then
  swiftlint
else
  echo "warning: SwiftLint not installed, download from https://github.com/realm/swiftlint"
fi
```

**SwiftFormat Check Run Script:**

This script will fail the build if formatting is incorrect, but it will not modify files.

```sh
export PATH="$PATH:/opt/homebrew/bin"

if which swift-format > /dev/null; then
  swift-format --lint -r TableGlass/ TableGlassKit/
else
  echo "warning: swift-format not installed, download from https://github.com/apple/swift-format"
fi
```

### Documentation Generation

API documentation is generated using `swift-doc`. A helper script is provided.

1.  **Make the script executable** (only needs to be done once):
    ```sh
    chmod +x generate-docs.sh
    ```
2.  **Run the script:**
    ```sh
    ./generate-docs.sh
    ```

The generated HTML documentation will be placed in the `docs/` directory, which is ignored by Git.
