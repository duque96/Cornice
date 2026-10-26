#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Cornice"
APP_DIR="dist/${APP_NAME}.app"

echo "Compilando ${APP_NAME}…"
swift build -c release --product "${APP_NAME}"

mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

cp ".build/release/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"

# Firma ad-hoc: suficiente para ejecutarlo localmente.
codesign --force --sign - "${APP_DIR}"

echo "Construido: ${APP_DIR}"
echo "Para ejecutarlo: open \"${APP_DIR}\""
