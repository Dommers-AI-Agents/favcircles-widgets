# FavWidgets

The mini-apps behind the **Widgets** tab on the FavCircles home screen: water,
habits, calories, workouts, bill split, postcards — the 10% of a popular app
people use every day, inside FavCircles.

## Modules

| Module | What | Depends on |
|---|---|---|
| `FavWidgetsCore` | The host contract (`FavWidgetHost`, `WidgetDataStore`), models, pure logic, the sync controller. Foundation only, so `swift test` runs on a Mac. | – |
| `FavWidgets` | SwiftUI: `FavWidget`, `WidgetContext`, the registry, the tab/card/manage views, and every widget. | Core |

The app links the single `FavWidgets` product and gets both.

## Data model

Every widget owns opaque JSON documents the server never interprets:

- one **settings/single** document under the widget id (`water`, `habits`, `billsplit`, `prefs`)
- for entry-style widgets, one **log document per month** (`calories_2026-09`, `workouts_2026-09`, `postcard_2026-09`)

Documents carry a `version`; saves are optimistic and a `409` hands back the
server's copy so `WidgetModel.merge(local:remote:)` can reconcile. Nothing is
ever pruned: retention is solved by sharding and compact encodings (per-month
int arrays, bit-strings), never by deleting user data.

## Adding a widget

1. Model(s) in `Sources/FavWidgetsCore/Models/` (`WidgetModel`: `empty` + optional `merge`).
2. Pure logic in `Sources/FavWidgetsCore/Logic/` with tests.
3. A folder under `Sources/FavWidgets/Widgets/<Name>/` with `<Name>Widget`, `<Name>CardView`, `<Name>FullView`.
4. One line in `FavWidgetRegistry.all`.

Rules: no UIKit in Core; iOS-only SwiftUI API behind `#if os(iOS)`; colors via
`context.theme`; every side effect through `context.host`; cards render from
cached state with no network and carry no text fields.

## Tests

```
swift test            # Core + registry tests on macOS
```

## Versioning

Tags: `0.x.0` when the host contract changes, `0.x.y` for widget-only changes.
The app pins `upToNextMinorVersion`.

## Changing a widget's document shape

A widget's synced document is plain `Codable`; unknown keys are dropped on
decode and a save writes the whole struct back. So an older build that
opens a newer document would silently strip the new fields and save that
over the server copy. The backend guards against this by refusing a save
whose `schemaVersion` is lower than the stored document's (`SCHEMA_TOO_OLD`).
That guard only works if the version moves, so **every change to a
document's shape bumps `schemaVersion` on that widget's descriptor**, and the
new decoder tolerates the old shape (`decodeIfPresent` with defaults, or an
explicit migration). Stocks went 1 → 2 when `entries` became `lists`.
