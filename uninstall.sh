#!/bin/bash
set -euo pipefail

APP="Cornice"
LABEL="com.duque.cornice"
DEST="$HOME/Applications/${APP}.app"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
UID_NUM="$(id -u)"

launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
pkill -x "$APP" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "$DEST"

echo "Cornice desinstalado."
echo "Se conservan ajustes, widgets y secretos en ~/Library/Application Support/Cornice."
