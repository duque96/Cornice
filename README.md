# Cornice

A modular host for the MacBook notch. The notch becomes a surface for widgets, and widgets are things anyone can build — not a fixed feature list.

- **Cornice** — the app (host, layout, permissions, settings)
- **CorniceKit** — the widget SDK
- **CorniceJS** — the sandboxed HTML/JS widget runtime

## Status

**M5 — the Example widget is a disk widget.** Nothing about it is compiled in anymore: it
ships as a bundled `.cornicewidget` (HTML/JS), authenticates through host-injected
credentials and is installed into Application Support on first run.

| Milestone | Content | Done |
|---|---|---|
| M0 | Surface, geometry, state machine | ✅ |
| M1 | Options window, persisted settings | ✅ |
| M2 | `CorniceKit` SDK + `CorniceHost` (mount, clock, capabilities) | ✅ |
| M3 | First widget: Example Widget usage (native) | ✅ |
| M4 | Widgets from disk (HTML/JS in a sandbox) + gallery | ✅ |
| M5 | Example Widget ported to a bundled disk widget + credential injection | ✅ |
| M6 | Layout solver with pages, native bundles with signatures | — |

## The Example Widget widget

`BundledWidgets/ExampleWidget.cornicewidget` is the reference implementation of a disk
widget. It shows the three usage windows (5h rolling, weekly, monthly) with color
thresholds, a progress bar and the time until reset, refreshing every 60 s **only while the
panel is visible**.

It never sees the API key. The manifest declares a credential:

```json
"credentials": [
  { "host": "example.com", "header": "Authorization", "prefix": "Bearer ",
    "keychain": { "service": "com.duque.cornice", "account": "opencode-api-key" } }
]
```

and the host attaches the header on the way out. The secret is imported once from
`~/.config/example-usage/key` and stored at
`~/Library/Application Support/Cornice/secrets/com.duque.cornice/opencode-api-key` with
mode `0600`. It is a file rather than a Keychain item on purpose: ad-hoc signed builds
change signature on every rebuild, and macOS would re-prompt on each one.

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
  "capabilities": ["network", "keychain"],
  "networkHosts": ["example.com"],
  "keychainServices": ["com.duque.cornice"],
  "credentials": [
    { "host": "example.com", "header": "Authorization", "prefix": "Bearer ",
      "keychain": { "service": "com.duque.cornice", "account": "example-token" } }
  ],
  "placement": { "columns": 6, "rows": 3 },
  "refresh": { "interval": 60 },
  "entry": "index.html",
  "defaultEnabled": false
}
```

The page talks to the host through `window.cornice`:

```js
const res = await cornice.fetch("https://example.com/data.json"); // { status, text }
cornice.onTick((timestamp) => { /* once per second while visible */ });
```

Disk widgets start **disabled** unless the manifest sets `defaultEnabled`. Enable them in
*Options → Widgets*, where you can also reveal the folder and reload. Widgets shipped in
the app bundle (`BundledWidgets/`) are installed on first run and replaced automatically
when their version increases; your own folders are never overwritten. They run in a `WKWebView` with a non-persistent data store,
no file access, no Keychain, no `URLSession`, and navigation confined to the bundle. The
only way out is `cornice.fetch`, which goes through the same host allow-list and rate limit
as native widgets.

Copy `Examples/ClockWidget.cornicewidget` there to try it.

## Capabilities

A widget declares what it needs in its manifest; the host decides what it actually gets.

| Capability | Injected as | Enforced by |
|---|---|---|
| `.network` | `WidgetContext.http` | host allow-list (`networkHosts`, exact host or subdomain) and 30 requests/minute |
| `.keychain` | `WidgetContext.secrets` + credential injection | scoped to `keychainServices`; other services return `nil`, and the secret is attached host-side |
| credentials | `Authorization` (or the declared header) | only for `credential.host`, only for the declared service/account; the value never reaches JS |

No capability means no object: `context.http` and `context.secrets` are `nil`, and the
manifest is rejected at mount time if it declares a capability without its allow-list, if a
credential points to a service outside `keychainServices`, or to a host outside
`networkHosts`.

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
BundledWidgets/
  ExampleWidget.cornicewidget/   # ships with the app
Examples/
  ClockWidget.cornicewidget/     # drop-in demo
Tests/
```

Dependency rule: `CorniceKit` imports nothing from the host. Widgets depend on `CorniceKit` only.

Inside `CorniceCore` the interaction is split in two on purpose:

- `NotchInteractionMachine` — pure state machine (`dormant → armed → open`), no timers, no AppKit. Fully unit tested.
- `NotchSurfaceController` — owns the clock, the `NSPanel` and the event monitors.

`NotchGeometryMath` is pure too, so the notch arithmetic is tested without a display.

## License

TBD.
