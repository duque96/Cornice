# Cornice

A modular host for the MacBook notch. The notch becomes a surface for widgets, and widgets are things anyone can build — not a fixed feature list.

- **Cornice** — the app (host, layout, permissions, settings)
- **CorniceKit** — the widget SDK
- **CorniceJS** — the sandboxed HTML/JS widget runtime

Status: pre-M0. Nothing implemented yet.

## Architecture

Full design notes live in the project conversation; they will land in `Docs/` before code.

```
Sources/
  CorniceCore/      # notch geometry, panel, animation, input
  CorniceKit/       # public SDK contract (no AppKit)
  CorniceHost/      # registry, layout, scheduler, capability broker
  CorniceUI/        # settings, widget gallery
  CorniceJS/        # WKWebView runtime (later)
  CorniceApp/       # @main, composition root
Widgets/            # built-in widgets (NowPlaying, Calendar, Shelf)
Tests/
```

Dependency rule: `CorniceKit` imports nothing from the host. Widgets depend on `CorniceKit` only.

## License

TBD.
