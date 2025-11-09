# AGENTS.md

## Project Vision

TableGlass is a macOS-native, SwiftUI-based database management tool.
Agents should prioritize **performance**, **UI responsiveness**, and **security** over feature quantity.
Target users are developers who prefer native macOS applications over Electron-based ones.

## Agent Roles

- **DesignAgent**
  Generates SwiftUI view layouts and UI prototypes.
  Must follow macOS Human Interface Guidelines and avoid adding unnecessary animations.

- **CodeAgent**
  Writes Swift + SwiftUI code that adheres to SwiftLint and SwiftFormat rules.
  Focus on testability and modularity (MVVM preferred).
  Avoid third-party dependencies unless specified in `Dependencies.md`.

- **DocAgent**
  Maintains README.md and Specification.md consistency.
  Updates code examples when API changes are detected.

- **TestAgent**
  Generates and runs unit/UI tests.
  Must ensure that database connections are mocked for CI runs.
  Real DB access tests are allowed only under `LocalDebug` configuration.

- **ReleaseAgent**
  Handles version bumping, notarization, and App Store upload scripts.
  Tags releases following `vX.Y.Z` semantic versioning.

## Coding Standards

- Use **Swift Concurrency** (`async/await`) for all DB operations.
- UI must remain responsive at all times.
- Database drivers: PostgresNIO, MySQLNIO, sqlite3 (system).
- Avoid blocking calls and global state.
- Separate business logic into a `Core` module for easier testing and future cross-platform use.

## Build and Run Instructions (for CI Agents)

1. Build with Xcode 16+ on macOS 15+
2. Run `swift test` with mocked databases.
3. Use `swiftlint` and `swiftformat` before any commit.
4. Generate docs with `swift doc` into `/docs` directory.

## Security Guidelines

- Never include real credentials in source or commits.
- `.env.example` is provided for local setup.
- SSH and SSL configuration must use the macOS Keychain API.
- Test databases must contain only synthetic data.

## Collaboration Rules

- Human developers review all AI-generated PRs before merge.
- AI commits must include `[auto-generated]` in the message.
- Agents should create small, focused PRs (< 500 lines).
- Human reviewers ensure UX and visual design consistency.
