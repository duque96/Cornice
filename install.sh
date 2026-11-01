#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

./build-app.sh

APP="Cornice"
LABEL="com.duque.cornice"
DEST="$HOME/Applications/${APP}.app"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG_DIR="$HOME/Library/Logs/Cornice"
UID_NUM="$(id -u)"

mkdir -p "$HOME/Applications" "$LOG_DIR" "$(dirname "$PLIST")"

# Stop the running copy and the previous agent, if any.
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
pkill -x "$APP" 2>/dev/null || true
sleep 1

rm -rf "$DEST"
cp -R "dist/${APP}.app" "$DEST"

cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${LABEL}</string>
	<key>ProgramArguments</key>
	<array>
		<string>${DEST}/Contents/MacOS/${APP}</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>ProcessType</key>
	<string>Interactive</string>
	<key>StandardOutPath</key>
	<string>${LOG_DIR}/out.log</string>
	<key>StandardErrorPath</key>
	<string>${LOG_DIR}/err.log</string>
</dict>
</plist>
PLISTEOF

launchctl bootstrap "gui/$UID_NUM" "$PLIST"
launchctl enable "gui/$UID_NUM/$LABEL" 2>/dev/null || true

echo "Instalado en ${DEST}"
echo "LaunchAgent: ${PLIST} (arranca al iniciar sesión)"
echo "Logs: ${LOG_DIR}/err.log"
