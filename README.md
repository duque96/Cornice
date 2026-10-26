# Cornice

A modular host for the MacBook notch. The notch becomes a surface for widgets, and widgets are things anyone can build — not a fixed feature list.

- **Cornice** — the app (host, layout, permissions, settings)
- **CorniceKit** — the widget SDK
- **CorniceJS** — the sandboxed HTML/JS widget runtime

## Status

**M0 — notch surface.** The panel, geometry, hover state machine and the options window
work. There are no widgets yet; the expanded surface shows placeholders for where they
will land.

| Milestone | Content | Done |
|---|---|---|
| M0 | Surface, geometry, state machine | ✅ |
| M1 | Hardware quirks: multi-display, fullscreen, simulated notch polish | — |
| M2 | `CorniceKit` + host + layout solver | — |
| M3 | Built-in widgets (Now Playing, Calendar, Shelf) | — |
| M4 | Settings + widget gallery + capability grants | — |
| M5 | `CorniceJS` runtime | — |

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
  CorniceKit/       # public SDK contract (no AppKit) — M2
  CorniceHost/      # registry, layout, scheduler, capability broker — M2
  CorniceUI/        # settings, widget gallery — M4
  CorniceJS/        # WKWebView runtime — M5
  CorniceApp/       # @main, composition root
Widgets/            # built-in widgets — M3
Tests/
```

Dependency rule: `CorniceKit` imports nothing from the host. Widgets depend on `CorniceKit` only.

Inside `CorniceCore` the interaction is split in two on purpose:

- `NotchInteractionMachine` — pure state machine (`dormant → armed → open`), no timers, no AppKit. Fully unit tested.
- `NotchSurfaceController` — owns the clock, the `NSPanel` and the event monitors.

`NotchGeometryMath` is pure too, so the notch arithmetic is tested without a display.

## License

TBD.
