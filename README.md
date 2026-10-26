# Cornice

A modular host for the MacBook notch. The notch becomes a surface for widgets, and widgets are things anyone can build — not a fixed feature list.

- **Cornice** — the app (host, layout, permissions, settings)
- **CorniceKit** — the widget SDK
- **CorniceJS** — the sandboxed HTML/JS widget runtime

## Status

**M0 — notch surface.** The panel, geometry and hover state machine work. There are no widgets yet; the expanded surface shows placeholders for where they will land.

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

Hover the notch to expand. The status bar icon toggles the surface and quits.

Debug switches (environment variables):

| Variable | Effect |
|---|---|
| `CORNICE_SIMULATE=1` | Draw a fake notch instead of using the hardware one |
| `CORNICE_START_OPEN=1` | Start with the surface expanded (design review) |
| `CORNICE_DEBUG=1` | Log state transitions to stderr |
| `CORNICE_OPEN_RESPONSE` | Opening spring response in seconds (default `0.30`) |
| `CORNICE_OPEN_DAMPING` | Opening spring damping (default `0.90`) |
| `CORNICE_CLOSE_RESPONSE` | Closing spring response (default `0.24`) |
| `CORNICE_CLOSE_DAMPING` | Closing spring damping (default `0.96`) |
| `CORNICE_CONTENT_DELAY` | Seconds before the content fades in (default `0.24`) |
| `CORNICE_CONTENT_DURATION` | Content fade duration (default `0.16`) |

The content is laid out once at its final size and revealed by a mask shaped like the
silhouette, so nothing reflows while the spring runs. `SurfaceSnapshotTests` renders
the surface and a filmstrip of the transition to `$CORNICE_SNAPSHOT_DIR`:
`CORNICE_SNAPSHOT_DIR=/tmp/cornice swift test --filter SurfaceSnapshotTests`.

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
