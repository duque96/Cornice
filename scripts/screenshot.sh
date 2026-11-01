#!/bin/bash
set -euo pipefail

# Captures the notch panel (layer 27) or the Options window (layer 0) by region.
# Usage: ./scripts/screenshot.sh [layer] [output.png]

cd "$(dirname "$0")/.."

LAYER="${1:-27}"
OUT="${2:-/tmp/cornice-$(date +%H%M%S).png}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/bounds.swift" <<'SWIFT'
import CoreGraphics
let want = Int(CommandLine.arguments[1]) ?? 27
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerName as String] as? String) == "Cornice" {
    let layer = w[kCGWindowLayer as String] as? Int ?? -1
    guard layer == want, let b = w[kCGWindowBounds as String] as? [String: Any] else { continue }
    let width = b["Width"] as? Double ?? 0
    let height = b["Height"] as? Double ?? 0
    guard width > 100, height > 20 else { continue }
    print("\(Int(b["X"] as? Double ?? 0)) \(Int(b["Y"] as? Double ?? 0)) \(Int(width)) \(Int(height))")
    break
}
SWIFT

BOUNDS="$(swift "$TMP/bounds.swift" "$LAYER" | head -1)"

if [ -z "$BOUNDS" ]; then
  echo "No hay ventana de Cornice en pantalla para layer $LAYER." >&2
  echo "Con el agente cargado, el panel duerme: usa CORNICE_START_OPEN=1 tras bootout." >&2
  exit 1
fi

RECT="$(echo "$BOUNDS" | awk '{printf "%d,%d,%d,%d", $1-8, $2-2, $3+16, $4+8}')"
screencapture -x -R "$RECT" "$OUT"
echo "$OUT"
