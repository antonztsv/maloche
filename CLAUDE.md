# maloche

Native macOS menu bar time tracker. At an interval it asks "What are you working on?" and books the elapsed span to the answer. Open source, MIT, local only: no server, no account, no telemetry, no network access.

## Stack

- Swift 6, SwiftUI with AppKit where SwiftUI falls short (`NSStatusItem`, `NSPanel`, `NSMenu`, Carbon hotkeys).
- Swift Package Manager only, no Xcode project. `scripts/build-app.sh` assembles and signs the `.app` bundle.
- Minimum macOS 26. No App Sandbox.
- GRDB for SQLite is the only dependency. Ask before adding another one.
- Swift Testing for tests.
- Look up current library and framework docs (Context7) before using an API you are not sure about.

## Layout

- `Sources/MalocheCore`: domain logic and storage. No AppKit or SwiftUI imports. Clock and idle detection are injected protocols.
- `Sources/Maloche`: the app (menu bar, panels, windows).
- `Tests/MalocheCoreTests`: unit and database tests.
- `scripts/`: build, signing, screenshots, release.

## Conventions

- Store timestamps in UTC. Day boundaries and display use local time; handle DST and midnight.
- Time blocks never overlap. Rounding is applied to output only, stored times stay exact.
- UI uses system text styles, semantic system colors and standard controls. No hard-coded colors for text, backgrounds, separators or accent.
- All user-facing strings live in the String Catalog. English is the source language.
- UI copy is positive and calm: no "open", "missing", "lost" or "gap", no countdowns, no "·" as a separator.
- Comments only for constraints the code cannot show, one line, English.

## Checks

```bash
swift build
swift test
xcrun swift-format lint --recursive Sources Tests
scripts/build-app.sh
scripts/screenshots.sh
```

Run scoped tests while iterating (`swift test --filter <Suite>`), the full suite before closing a milestone. Report scoped runs as scoped.

## Tests

- Tests first, and see them fail before implementing.
- Domain rules get unit tests with a simulated clock. Storage gets database tests against an in-memory GRDB database.
- UI is checked with screenshots in light and dark mode from `scripts/screenshots.sh`.

## Data and secrets

- No real personal data in the repo, tests, fixtures, screenshots or logs. Fixtures and seeds are synthetic.
- The local code signing certificate stays in the keychain and never enters the repo.

## Git

- Commit locally after each finished task without asking, one commit per task, on the main branch.
- Stage files by name. Never `git add -A` or `git add .`.
- Commit messages are one line: `<type>: <description>`, types `feat`, `fix`, `docs`, `chore`, lowercase, imperative, max 72 characters. No body, no co-author or attribution trailers.
- Never push, add a remote, force-push, rewrite history, tag or delete branches.
