# Specifications

## About TableGlass

TableGlass is a macOS-native database management tool built with SwiftUI. It aims to stay lightweight, responsive, and secure while supporting PostgreSQL, MySQL, and SQLite drivers. Database access is async/await, and SSH/Keychain integration is required for secrets and tunnels.

## Startup and Window Flow

- Launch opens the **Connection Management** window. This is the entry point for creating or selecting a connection profile.
- Pressing **Connect** saves the current draft (to Keychain where applicable) and opens a new **Database Browser** window for that profile. Each connect action creates a new browser window so multiple live connections can exist side by side.
- Each Database Browser window can host multiple sessions as tabs (macOS NSTabView). A placeholder view appears when no sessions are loaded.
- Opening the Database Browser scene directly (menu or shortcut) auto-loads saved connections in read-only mode when a `ConnectionStore` is available; otherwise it shows the placeholder until a connection is made.

## Connection Management Window

- Sidebar lists saved connections; the detail pane edits the selected profile or a new draft. Required fields: display name, database kind, host, port, username; password can be stored securely.
- SSH tunneling is configurable per connection:
  - Host aliases are parsed from `~/.ssh/config` and selectable.
  - Key-based auth uses macOS Keychain persistent references; passwords and private keys are never stored in plaintext.
  - SSH agent status is surfaced; real tunnels only run under the `LocalDebug` build, while tests rely on mocks.
- Actions: **New Connection** creates a fresh draft, **Save** persists changes, **Delete** removes the profile (with Keychain cleanup), **Connect** triggers the browser launch flow. Errors surface inline above the form.

## Database Browser Layout

- **Header**: shows connection status dot + name, status text, a **Show Log** button (opens the per-session query log), and a **Read-Only** toggle. Sessions start in read-only mode by default; switching modes always prompts with a confirmation dialog that requires a checkbox acknowledgement.
- **Sidebar**: tree of catalogs → namespaces/schemas → tables, views, stored procedures. Controls include Refresh (reload metadata), Expand All/Collapse All (with progress indicator while expanding), and lazy loading of children when expanding nodes.
- **Detail area** (right pane):
  - **Query editor** card at the top with a monospaced TextEditor and a **Run** button. A spinner appears while executing. In read-only mode, the editor shows a lock hint if the text is not safe to execute.
  - **Object header** beneath the editor displays the selected object's name, type icon, and fully qualified path, or a prompt when nothing is selected.
  - **Detail content**: when a table is selected, a segmented control switches between **Results** and **Table Editor**. For other objects or no selection, the Results view is shown.

## SQL Execution Model

- Selecting a table populates the editor with a default query and runs it immediately in read-only mode: `SELECT * FROM "<schema>"."<table>" LIMIT 50;` (schema omitted when empty, identifiers are quoted; limit defaults to 50).
- The **Run** button trims the editor text; empty input is ignored. Execution is disabled while a query is in flight.
- Read-only enforcement blocks statements that start with or contain mutation keywords (INSERT/UPDATE/DELETE/ALTER/CREATE, etc.). When blocked, the Run button is disabled and an inline notice explains the restriction.
- Results render in the **Query Results** section beneath the object header: row count, affected row count (when provided), and a scrollable, read-only grid of returned rows. When no rows are returned, a placeholder message is shown.
- Errors surface inline in the results area with a warning icon and a **Retry** button that reuses the current SQL. The editor retains the text so users can adjust and rerun.

## Table Data Editor

- Available when a table is selected and the **Table Editor** tab is active. Uses table metadata to render columns (name + type), row status, and actions.
- Buttons: **Add Row** (seeds defaults/nulls), **Delete** (with confirmation for selected rows), **Save** per row. All mutation controls are disabled in read-only mode or while a mutation is running.
- Row status shows Saved/Unsaved/Error with inline validation errors; banner errors appear at the top when fetch or mutation fails.
- Pagination streams rows in pages (default 50); **Load More** appears at the end and prefetches automatically as you scroll.

## Query History and Logging

- Every executed statement (success or failure) is recorded in `DatabaseQueryHistory` with capacity 5,000 entries. History is persisted to `UserDefaults` and is effectively shared across sessions/windows because each session loads from the same store.
- **History navigation**: `cmd+option+↑` loads the previous entry; `cmd+option+↓` moves forward and restores the in-editor draft. Navigation resets if the text changes.
- **History search overlay** (`ctrl+R`): shows a search field and preview. `↑/↓` change the highlighted match, `Return` inserts it into the editor and closes the overlay, `Esc` cancels and refocuses the editor.
- **Query log**: the **Show Log** button opens a session-scoped log window listing timestamped SELECT/INSERT/UPDATE/DELETE statements executed through that browser session.

## Keyboard Shortcuts

- Run query: click **Run** (no dedicated shortcut yet; planned `cmd+return` once wired).
- Toggle read-only: header switch with confirmation dialog (no shortcut; planned).
- SQL history: `cmd+option+↑/↓` (back/forward), `ctrl+R` to open search, `Return` to insert match, `Esc` to cancel search.
- Connections and windows: `cmd+N` New Connection, `cmd+shift+M` Manage Connections, `cmd+shift+B` New Database Browser Window. Standard macOS window/tab navigation applies for browser tabs and windows.

## Planned/Upcoming Behavior

- **Unified results grid**: planned consolidation so ad-hoc query results and table editor share the same grid component, column metadata, and (where allowed) inline editing, still respecting read-only mode.
- **SQL execution UX**: add a keyboard shortcut for Run and optional toolbar affordance for history/search to reduce pointer travel.
- **History scoping**: option to filter or scope history per connection profile while keeping the persisted backing store.
