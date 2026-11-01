# Cornice

A modular host for the MacBook notch. The notch becomes a surface for widgets, and widgets are things anyone can build — not a fixed feature list.

- **Cornice** — the app (host, layout, permissions, settings)
- **CorniceKit** — the widget SDK
- **CorniceJS** — the sandboxed HTML/JS widget runtime

## Status

**M4 — widgets from disk.** The surface, the options window, the SDK, the host and the
first widget all work. Widgets are no longer compiled in: drop a `*.cornicewidget` bundle
in Application Support and enable it from Options.

| Milestone | Content | Done |
|---|---|---|
| M0 | Surface, geometry, state machine | ✅ |
| M1 | Options window, persisted settings | ✅ |
| M2 | `CorniceKit` SDK + `CorniceHost` (mount, clock, capabilities) | ✅ |
| M3 | First widget: Example Widget usage | ✅ |
| M4 | Widgets from disk (HTML/JS in a sandbox) + gallery | ✅ |
| M5 | Layout solver with pages, native bundle loading with signatures | — |

## The first widget

`Widgets/ExampleWidget` shows the three usage windows (5h rolling, weekly, monthly) with
per-window color thresholds, a progress bar and the time until reset. It refreshes
every 60 s **only while the panel is visible**, and retries every 20 s after a failure.

It only ever reads Cornice's Keychain item (`com.duque.cornice` / `opencode-api-key`).
At launch, Cornice imports `~/.config/example-usage/key` into that item once: no prompts
and no cross-app Keychain access.

## Widgets from disk

A widget is a folder in `~/Library/Application Support/Cornice/Widgets`:

```
ClockWidget.cornicewidget/
  manifest.json
  index.html
```

```json
{
  "id": "com.example.clock",
  "name": "Clock",
  "version": "1.0.0",
  "apiVersion": 1,
  "capabilities": ["network"],
  "networkHosts": ["example.com"],
  "placement": { "columns": 6, "rows": 3 },
  "refresh": { "interval": 60 },
  "entry": "index.html"
}
```

The page talks to the host through `window.cornice`:

```js
const res = await cornice.fetch("https://example.com/data.json"); // { status, text }
cornice.onTick((timestamp) => { /* once per second while visible */ });
```

Disk widgets start **disabled**: enable them in *Options → Widgets*, where you can also
reveal the folder and reload. They run in a `WKWebView` with a non-persistent data store,
no file access, no Keychain, no `URLSession`, and navigation confined to the bundle. The
only way out is `cornice.fetch`, which goes through the same host allow-list and rate limit
as native widgets.

Copy `Examples/ClockWidget.cornicewidget` there to try it.

## Capabilities

A widget declares what it needs in its manifest; the host decides what it actually gets.

| Capability | Injected as | Enforced by |
|---|---|---|
| `.network` | `WidgetContext.http` | host allow-list (`networkHosts`, exact host or subdomain) and 30 requests/minute |
| `.keychain` | `WidgetContext.keychain` | scoped to `keychainServices`; any other service returns `nil` |

No capability means no object: `context.http` and `context.keychain` are `nil`, and the
manifest is rejected at mount time if it declares a capability without its allow-list.

The contract is also checked at build time: `testWidgetSourcesDoNotBypassTheHost` fails if
any file under `Widgets/` mentions `URLSession`, `FileManager`, `SecItem`, `NSWorkspace`,
`NSPasteboard` or `Process(`. An in-process Swift widget could technically bypass the host,
so this test is what keeps first-party widgets honest until the JS runtime lands.

## Run it

```bash
swift build && swift test      # library + unit tests
./build-app.sh                 # dist/Cornice.app
open dist/Cornice.app
```

Hover the notch to expand. The status bar icon toggles the surface, opens **Options…**
(`⌘,`) and quits. The gear inside the expanded panel does the same.

## Options

Everything the surface uses is editable and applied live from **Options…**: open/close
spring (response + bounce), content fade delay and duration, hover open/close delays, and
panel width/height. `Show notch` pins the surface open so changes can be previewed while
you drag the sliders.

Settings persist to `~/Library/Application Support/Cornice/settings.json` (atomic writes,
schema version, values clamped on load).

| Variable | Effect |
|---|---|
| `CORNICE_SIMULATE=1` | Draw a fake notch instead of using the hardware one |
| `CORNICE_START_OPEN=1` | Start with the surface expanded (design review) |
| `CORNICE_START_SETTINGS=1` | Open the options window on launch |
| `CORNICE_DEBUG=1` | Log state transitions to stderr |

The content is laid out once at its final size and revealed by a mask shaped like the
silhouette, so nothing reflows while the spring runs. `SurfaceSnapshotTests` and
`SettingsTests` render the surface, a filmstrip of the transition and the options form to
`$CORNICE_SNAPSHOT_DIR`:

```bash
CORNICE_SNAPSHOT_DIR=/tmp/cornice swift test
```

## Architecture

```
Sources/
  CorniceCore/      # notch geometry, panel, animation, input
  CorniceKit/       # public SDK: manifests, capabilities, CorniceWidget
  CorniceHost/      # mounting, clock, capabilities, disk loader, web sandbox
  CorniceApp/       # @main, composition root
Widgets/
  ExampleWidget/    # first widget (compiled in)
Examples/
  ClockWidget.cornicewidget/
Tests/
```

Dependency rule: `CorniceKit` imports nothing from the host. Widgets depend on `CorniceKit` only.

Inside `CorniceCore` the interaction is split in two on purpose:

- `NotchInteractionMachine` — pure state machine (`dormant → armed → open`), no timers, no AppKit. Fully unit tested.
- `NotchSurfaceController` — owns the clock, the `NSPanel` and the event monitors.

`NotchGeometryMath` is pure too, so the notch arithmetic is tested without a display.

## License

TBD.
