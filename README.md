# TableGlass

TableGlass is an open-source database management tool.
Designed for macOS. Built using SwiftUI. It aims to be lightweight and easy to use. Compatible with databases such as PostgreSQL, MySQL and Sqlite3.

## Features

- **Multi-Database Support**: Planned support for PostgreSQL, MySQL, and Sqlite3 databases.
- **Intuitive UI**: An easy-to-use interface makes database management easy.
- **Open Source**: The source code is available on GitHub, and community contributions are welcome.

## Architecture Overview

- `Core`: A Swift framework that defines shared business logic and dependency contracts for database access.
- `TableGlass`: The SwiftUI application target that builds the user interface and consumes `Core` via dependency injection.
