# Specifications

## About TableGlass

TableGlass is an open-source database management tool for macOS. Built with SwiftUI, it aims to be lightweight and easy to use. It is compatible with databases such as PostgreSQL, MySQL, and Sqlite3.

## Features

- **Multi-Database Support**: Support for PostgreSQL, MySQL, and Sqlite3 databases is planned.
- **Intuitive UI**: The easy-to-use interface makes database management easy.

## Screens

### Connection Management Window

- The Connection Management window allows you to add, edit, and delete database connections. Each connection can be configured with information such as the name, database type, and host. Additional settings include port, username, and password.
- Optionally connect using an SSH tunnel.
  - Configurable from the ~/.ssh/config file.
  - SSH key authentication is resolved through the macOS Keychain; no secrets are stored in plain text.
  - Users choose which Keychain identity to use when enabling a tunnel; TableGlass retains only the persistent reference.
  - Real SSH tunnels execute only under the `LocalDebug` configuration. Test and CI builds must rely on mocked SSH services.

### Database Browser Window

- When you connect to a database, the Database Browser window opens.
- The Database Browser window is tabbed, allowing you to connect to multiple databases simultaneously.
- Multiple Database Browser windows can be opened.
- Each window contains the following elements:
  - The top of the window displays the name and status of the connected database.
  - A Show Log button next to the database name opens a log window.
    - The log lists time-stamped `SELECT`, `INSERT`, `UPDATE`, and `DELETE` statements from this window.
  - Place a toggle button next to the database name to switch between read only and writable mode.
    - Changes to this toggle button are confirmed in a modal dialog before applying.
    - In the modal dialog, check the "Confirm" checkbox to enable mode changes. Then press OK to apply.
  - The left sidebar displays a tree view of database objects.
    - Objects include tables, views, and stored procedures.
    - Clicking on the names of tables, views, etc. will display them in the main view.
  - The main view on the right displays detailed information about the selected object.
    - Selecting a table displays the table's data in a grid view.
    - Data can be edited, added, and deleted.
    - A query editor is also provided for directly executing SQL queries.
