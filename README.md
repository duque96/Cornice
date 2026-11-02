# Cornice

A modular host for the MacBook notch, built for developers and homelabs.

Cornice is not another media player. It is a small surface for the things you check while
you work — self-hosted services, CI, containers, network state, deployments — with a real
SDK so the widgets can be yours.

- **Cornice** — the app: surface, layout, capabilities, settings.
- **CorniceKit** — the widget SDK: manifest, capabilities, lifecycle, settings.
- **Widgets** — plain HTML/CSS/JS bundles with a manifest, loaded from disk.

## Why another notch app

- **Developer-first.** The interesting notch utilities are operational: is the server up, did
  CI pass, is the tunnel connected, what is the agent doing. Cornice is built around that,
  not around album artwork.
- **A real SDK, not a fixed feature list.** A widget is a folder with `manifest.json` and
  `index.html`. Declare what you need, the host decides what you get.
- **Capabilities are enforced by the host.** Network allow-lists, scoped secrets, credential
  injection and a fixed command surface for privileged integrations. No arbitrary shell.
- **Local-first.** No telemetry. Secrets never reach the widget.
- **Layout is yours.** Six-column grid, pages, drag to reorder, drag a corner to resize.

## Status

**M11 — the platform is usable.** Surface, options, SDK, host, disk widgets, capabilities,
grid with interactive paging, reorder, resize and English/Spanish.

| Milestone | Content | Done |
|---|---|---|
| M0 | Surface, geometry, state machine | ✅ |
| M1 | Options window, persisted settings | ✅ |
| M2 | `CorniceKit` SDK + `CorniceHost` (mount, clock, capabilities) | ✅ |
| M3 | First widget, HTML/JS from disk | ✅ |
| M4 | Widget gallery, enable/disable | ✅ |
| M5 | Credential injection, scoped secrets | ✅ |
| M6 | Sidebar options window + declarative widget settings | ✅ |
| M7 | 6-column grid with pages and interactive swipe | ✅ |
| M8 | Drag to reorder widgets | ✅ |
| M9 | Drag to resize widgets on the grid | ✅ |
| M10 | Capability-gated privileged integrations | ✅ |
| M11 | English and Spanish, down to the SDK | ✅ |
| M12 | Native signed bundles | — |

## Install

```bash
./install.sh
```

Builds, copies the app to `~/Applications/Cornice.app` and loads
`~/Library/LaunchAgents/com.duque.cornice.plist` (`RunAtLoad`, restart only on crash, logs
in `~/Library/Logs/Cornice/`). `./uninstall.sh` removes the app and the agent; settings and
widgets stay in Application Support.

Cornice is an accessory app (`LSUIElement`): no Dock icon. The menu bar icon is optional in
*Options → General*, and that page also has Quit. With it off, the app lives only in the notch.

For development:

```bash
swift build && swift test
./build-app.sh
launchctl bootout gui/$(id -u)/com.duque.cornice   # stop the agent before testing dist/
CORNICE_START_OPEN=1 CORNICE_DEBUG=1 dist/Cornice.app/Contents/MacOS/Cornice
```

## Widgets from disk

A widget is a folder in `~/Library/Application Support/Cornice/Widgets`:

```
ExampleWidget.cornicewidget/
  manifest.json
  index.html
```

```json
{
  "id": "com.example.status",
  "name": "Status",
  "version": "1.0.0",
  "apiVersion": 1,
  "capabilities": ["network"],
  "networkHosts": ["status.example.com"],
  "placement": { "columns": 3, "rows": 3 },
  "refresh": { "interval": 60 },
  "entry": "index.html",
  "defaultEnabled": false
}
```

The page talks to the host through `window.cornice`:

```js
const res = await cornice.fetch("https://status.example.com/api"); // { status, text }
cornice.onTick((timestamp) => { /* once per second while visible */ });
cornice.settings;   // declared settings, already resolved
cornice.language;   // "en" | "es"
```

Disk widgets start **disabled** unless the manifest sets `defaultEnabled`. Enable them in
*Options → Widgets*, where you can also reveal the folder and reload. Bundles shipped inside
the app are installed on first run and replaced only when their version increases; your own
folders are never overwritten.

They run in a `WKWebView` with a non-persistent data store, no file access, no Keychain, no
`URLSession`, and navigation confined to the bundle. The only way out is `cornice.fetch`,
which goes through the host allow-list and rate limit.

## Layout

Six-column grid: `placement.columns` is a span (1–6) and `placement.rows` sets the height
(30 pt per row plus 8 pt gaps). Widgets flow left to right, wrap, and move to another page
when a row does not fit; dots appear at the bottom.

The page follows a horizontal trackpad drag — the next page slides in as you swipe — and
settles on release with a spring. Dots are clickable too.

```
┌─────────────┬─────────────┐
│ Widget A    │ Widget B    │   3 + 3 columns, one page
│ 3×3         │ 3×2         │
└─────────────┴─────────────┘
```

Drag rows in *Options → Widgets* to reorder (persisted in `widgets.json`). In
*Options → Layout*, drag a widget's corner to resize it (1–6 × 1–8, persisted). The solver
`WidgetGridLayout.layout(widgets:available:)` is pure and unit-tested.

## Capabilities

A widget declares what it needs; the host decides what it actually gets.

| Capability | Injected as | Enforced by |
|---|---|---|
| `.network` | `WidgetContext.http` / `cornice.fetch` | host allow-list (`networkHosts`, exact host or subdomain) and 30 requests/minute |
| `.keychain` | `WidgetContext.secrets` | scoped to `keychainServices`; other services return `nil` |
| credentials | `Authorization` (or the declared header) | only for the declared host, service and account; the secret never reaches JS |

No capability means no object: `context.http` and `context.secrets` are `nil`, and the
manifest is rejected at mount time if it declares a capability without its allow-list, if a
credential points outside `keychainServices`, or to a host outside `networkHosts`.

Privileged integrations (device or service control) are separate capabilities, each with a
fixed command surface mediated by the host — never a shell.

## Localization

*Options → General → Language* offers **System / English / Español**. It applies live to the
window, the status menu and every widget.

- Native widgets read `WidgetContext.language` (`WidgetLanguage.en` / `.es`).
- Web widgets get `window.cornice.language` and `window.cornice.locale`.
- "System" resolves from the Mac's preferred language once.

The app UI uses a small inline translator, `Translator(language)("English", "Español")`, so
a language change re-renders immediately with no relaunch and no resource bundles.

## Options

A sidebar, one page per section, applied live:

| Section | What it holds |
|---|---|
| **General** | language, menu bar icon, quit |
| **Motion** | open/close spring, content fade delay and duration |
| **Interaction** | hover open/close delays |
| **Panel** | width, height, fit to content, restore defaults |
| **Layout** | visual grid editor: drag a corner to resize, reset sizes |
| **Widgets** | gallery: enable/disable, drag to reorder, source, capabilities, open folder, reload |
| **<widget name>** | one page per widget that declares settings |

`Show notch` pins the surface open so changes can be previewed. Sections are rebuilt every
time the window opens.

Host settings persist to `~/Library/Application Support/Cornice/settings.json` (atomic,
schema version, values clamped on load). Widget settings live in
`~/Library/Application Support/Cornice/widget-settings/<id>/settings.json`.

### Widget settings

A widget declares its fields and the host renders the form:

```json
"settings": [
  { "id": "refreshSeconds", "title": "Refresh every", "type": "number",
    "min": 30, "max": 600, "step": 10, "default": 60 },
  { "id": "compact", "title": "Compact layout", "type": "toggle", "default": false }
]
```

Types: `toggle`, `number` (requires `min`/`max`), `text`, `select` (requires `options`).
Values are validated and clamped on load. Changing one remounts the widget, so a web widget
reloads with `cornice.settings` already populated.

## Debug switches

| Variable | Effect |
|---|---|
| `CORNICE_SIMULATE=1` | Draw a fake notch instead of using the hardware one |
| `CORNICE_START_OPEN=1` | Start with the surface expanded and pinned |
| `CORNICE_START_SETTINGS=1` | Open the options window on launch |
| `CORNICE_DEBUG=1` | Log state transitions, widget mounts and fetches to stderr |

## Architecture

```
Sources/
  CorniceCore/      # notch geometry, panel, animation, input, settings shell
  CorniceKit/       # public SDK: manifests, capabilities, settings, CorniceWidget
  CorniceHost/      # mounting, clock, capabilities, disk loader, web sandbox, settings UI
  CorniceApp/       # @main, composition root, sidebar sections
BundledWidgets/     # one generic example widget
Tests/
```

Dependency rule: `CorniceKit` imports nothing from the host; `CorniceCore` imports neither
the SDK nor the host. Widgets only see `window.cornice` (or `WidgetContext` for native ones).

Inside `CorniceCore` the interaction is split on purpose:

- `NotchInteractionMachine` — pure `dormant → armed → open` state machine, no timers, no AppKit.
- `NotchSurfaceController` — owns the clock, the `NSPanel`, the event monitors and paging.

`NotchGeometryMath`, `WidgetGridLayout`, `WidgetResize` and `WidgetOrdering` are pure and
unit-tested.

## Tests

```bash
swift test
```

Geometry, hover state machine, interactive pager, settings clamping/migration, grid and pages,
ordering, resizing, disk loader, installer upgrades, capability enforcement, HTTP, manifest
contract, localization and a load test for the bundled example widget.

Snapshot helpers render the surface, a filmstrip of the transition and the options form to
`$CORNICE_SNAPSHOT_DIR`:

```bash
CORNICE_SNAPSHOT_DIR=/tmp/cornice swift test
```

## License

MIT. See `LICENSE`.
