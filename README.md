# TableGlass

TableGlass is an open-source database management tool.
Designed for macOS. Built using SwiftUI. It aims to be lightweight and easy to use. Compatible with databases such as PostgreSQL, MySQL and Sqlite3.

## Features

- **Multi-Database Support**: Planned support for PostgreSQL, MySQL, and Sqlite3 databases.
- **Intuitive UI**: An easy-to-use interface makes database management easy.
- **Open Source**: The source code is available on GitHub, and community contributions are welcome.

## Architecture Overview

- `TableGlassKit`: Swift framework providing shared business logic and database abstractions.
  - `Connections`: handles saved profiles and retrieval stores used by the UI layer.
  - `Database`: defines async/await protocols for connections and transactions.
    Schema metadata models live here.
    Placeholder factories for PostgresNIO/MySQLNIO/sqlite3 stay until driver integrations land.
- `TableGlass`: SwiftUI app target that renders the UI and injects `TableGlassKit` services.
