import Foundation

/// Single type scale for widget content. Widgets read these as CSS variables, so
/// sizes live here instead of being copied (and drifting) in every bundle.
/// `uiScale` is applied on top as `pageZoom`; nothing else multiplies type.
enum WidgetTypography {
    static let css = """
    :root {
      --cornice-font: -apple-system, system-ui, sans-serif;
      --cornice-mono: ui-monospace, SFMono-Regular, monospace;

      --cornice-title-size: 12px;
      --cornice-title-weight: 600;
      --cornice-label-size: 10px;
      --cornice-label-weight: 500;
      --cornice-value-size: 16px;
      --cornice-value-weight: 600;
      --cornice-meta-size: 9.5px;
      --cornice-meta-weight: 500;
      --cornice-mono-size: 9.5px;

      --cornice-ink: rgba(255, 255, 255, 0.95);
      --cornice-ink-label: rgba(255, 255, 255, 0.58);
      --cornice-ink-meta: rgba(255, 255, 255, 0.40);
      --cornice-ink-mono: rgba(255, 255, 255, 0.42);

      --cornice-green: #5cd68c;
      --cornice-amber: #ffb84d;
      --cornice-red: #ff6161;
    }
    """
}
