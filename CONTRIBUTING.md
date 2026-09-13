# Contributing a widget

- Ids: `^[a-z][a-z0-9-]{1,31}$`, no underscore (reserved for month shards), never `prefs`.
- Keep the model small and stable; bump `schemaVersion` when its shape changes.
- Storage: `.single` for counters/settings that stay small forever, `.monthly` for entry logs.
- Never delete or trim user data. Archive, don't remove.
- Card: `WidgetCard(context:action:) { … }`, one live summary, at most one quick action, no text fields.
- Full view: `WidgetSyncBadge` at the top, edits only through `controller.update { … }`.
- Build with `swift build`, test with `swift test`; both must be green on macOS.
