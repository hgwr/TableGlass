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

## Architecture Overview

- `TableGlassKit`: Swift framework providing shared business logic and database abstractions.
  - `Connections`: handles saved profiles and retrieval stores used by the UI layer.
  - `Database`: defines async/await protocols for connections and transactions.
    Schema metadata models live here.
    Placeholder factories for PostgresNIO/MySQLNIO/sqlite3 stay until driver integrations land.
- `TableGlass`: SwiftUI app target that renders the UI and injects `TableGlassKit` services.
