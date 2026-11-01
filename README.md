# Cornice

A modular host for the MacBook notch. The notch becomes a surface for widgets, and widgets are things anyone can build — not a fixed feature list.

- **Cornice** — the app (host, layout, permissions, settings)
- **CorniceKit** — the widget SDK
- **CorniceJS** — the sandboxed HTML/JS widget runtime

## Status

**M2 — SDK, host and the first widget.** The surface, the options window and a real widget
work: Example Widget usage, read from the same API as the ExampleWidget menu bar app.

| Milestone | Content | Done |
|---|---|---|
| M0 | Surface, geometry, state machine | ✅ |
| M1 | Options window, persisted settings | ✅ |
| M2 | `CorniceKit` SDK + `CorniceHost` (mount, clock, capabilities) | ✅ |
| M3 | First widget: Example Widget usage | ✅ |
| M4 | More widgets, layout solver with pages, capability grants UI | — |
| M5 | `CorniceJS` runtime | — |

## The first widget

`Widgets/ExampleWidget` shows the three usage windows (5h rolling, weekly, monthly) with
per-window color thresholds, a progress bar and the time until reset. It refreshes
every 60 s **only while the panel is visible**, and retries every 20 s after a failure.

The API key is looked up in this order:

1. Cornice's Keychain item (`com.duque.cornice` / `opencode-api-key`)
2. `~/.config/example-usage/key`
3. The Example Usage app's Keychain item (macOS will ask for permission)

It declares only `.network` and `.keychain` in its manifest, and the host gives it those
and nothing else. The legacy file fallback is a deliberate exception for headless setups:
there is no capability for arbitrary files yet.

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
  CorniceHost/      # mounting, activation, shared clock, keychain
  CorniceApp/       # @main, composition root
Widgets/
  ExampleWidget/    # first widget
Tests/
```

Dependency rule: `CorniceKit` imports nothing from the host. Widgets depend on `CorniceKit` only.

Inside `CorniceCore` the interaction is split in two on purpose:

- `NotchInteractionMachine` — pure state machine (`dormant → armed → open`), no timers, no AppKit. Fully unit tested.
- `NotchSurfaceController` — owns the clock, the `NSPanel` and the event monitors.

`NotchGeometryMath` is pure too, so the notch arithmetic is tested without a display.

## License

TBD.
