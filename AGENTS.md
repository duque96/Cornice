# AGENTS.md — Cornice

Contrato para agentes que trabajen en este repo. Léelo entero antes de tocar código.
Si algo aquí contradice al código, **gana el código**: corrige este documento en el mismo
commit.

Documentación de producto: `README.md` (en inglés, como la UI). Este archivo está en
español porque es la nota de trabajo.

---

## 1. Qué es Cornice

Host modular para el notch del MacBook. El notch es una superficie donde se montan widgets;
los widgets son bundles HTML/JS que se cargan desde disco, declaran capacidades y nunca
tocan el sistema directamente.

- **App**: `Cornice.app` (accesoria, sin Dock; icono de barra opcional).
- **SDK**: `CorniceKit` — manifiesto, capacidades, settings, contexto, `CorniceWidget`.
- **Host**: `CorniceHost` — montaje, reloj, capacidades, llavero, loader de disco, UI de ajustes.
- **Core**: `CorniceCore` — panel, geometría, animación, ajustes, localización.

Estado: M11. 87 tests. Instalado en `~/Applications/Cornice.app` bajo LaunchAgent
`com.duque.cornice` (arranque al login, sin icono de menú por decisión del usuario).

> Contexto del entorno: el usuario tiene un homelab (`proxmox` 192.0.2.10, dashboard en
> `:8123`). Si una tarea toca el homelab, aplica también `~/.config/opencode/AGENTS.md` y el
> repo `~/homeserver` (pull antes, nota después).

---

## 2. Mapa del repo

```
Sources/
  CorniceKit/        SDK: sin AppKit, sin Core, sin red propia
  CorniceCore/       panel, geometría, estado, ajustes, shell de Opciones
  CorniceHost/       host de widgets, loader de disco, sandbox web, UI de widgets
  CorniceApp/        @main, AppDelegate, composición de secciones
BundledWidgets/      widgets que viajan dentro de la app (.cornicewidget)
Tests/
  CorniceCoreTests/  geometría, máquina de estados, ajustes, pager
  CorniceKitTests/   contrato de manifiesto, HTTP
  CorniceHostTests/  layout, orden, tamaños, loader, capabilities
Resources/Info.plist
build-app.sh         compila release y arma dist/Cornice.app
install.sh           copia a ~/Applications + LaunchAgent
uninstall.sh
scripts/screenshot.sh
```

### Regla de dependencias

```
CorniceApp → CorniceHost → {CorniceCore, CorniceKit}
CorniceApp → CorniceCore (shell de Opciones, secciones)
CorniceCore → (nada)
Widgets de disco → solo ven el bridge JS, nunca Swift
```

- `CorniceKit` **no** importa Core/Host/AppKit. Es el contrato.
- `CorniceCore` **no** importa Kit ni Host.
- `CorniceHost` puede importar ambos y SwiftUI/WebKit.
- Un widget HTML no puede importar nada: solo `window.cornice`.

---

## 3. Build, test, install

```bash
swift build                      # debug
swift test                       # 87 tests
./build-app.sh                   # release + dist/Cornice.app (copia BundledWidgets a Resources)
./install.sh                     # ~/Applications + LaunchAgent (arranque al login)
./uninstall.sh                   # quita app y agente; conserva datos
```

### Gotcha de desarrollo (importante)

Con el LaunchAgent cargado, `pkill -x Cornice` **relanza la app al instante**
(`KeepAlive SuccessfulExit=false`). Puedes acabar con dos instancias peleándose por el
mismo panel, y las capturas enseñan el widget viejo. Para probar una build de `dist/`:

```bash
launchctl bootout gui/$(id -u)/com.duque.cornice
pkill -x Cornice
CORNICE_START_OPEN=1 CORNICE_DEBUG=1 dist/Cornice.app/Contents/MacOS/Cornice
# …probar…
./install.sh          # devolver el control a launchd
```

Reiniciar sin reinstalar: `launchctl kickstart -k gui/$(id -u)/com.duque.cornice`.

### Variables de entorno (solo debug)

| Variable | Efecto |
|---|---|
| `CORNICE_DEBUG=1` | Logs de estado, widgets y ajustes a stderr |
| `CORNICE_SIMULATE=1` | Notch simulado (pantallas sin notch) |
| `CORNICE_START_OPEN=1` | **Pinea** la superficie (revisión de diseño); se desancla al parar |
| `CORNICE_START_SETTINGS=1` | Abre Opciones al arrancar |

Logs de producción: `~/Library/Logs/Cornice/{out,err}.log`.

---

## 4. La superficie (CorniceCore)

### Ventana

`NotchPanel`: `NSPanel` borderless, `.nonactivatingPanel`, `canBecomeKey/Main = false`,
`level = mainMenu + 3`, `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`.

Reglas que no hay que romper:

1. **En reposo no hay ventana**: tras el colapso se hace `orderOut`. Si no, macOS congela
   una instantánea durante el swipe de espacios y se ve un rectángulo.
2. **La ventana no puede animarse por su cuenta**: al abrir se pone el frame final primero y
   luego SwiftUI anima la silueta dentro. Al cerrar se anima y se encoge 420 ms después.
3. `hostingView.sizingOptions = []`: sin esto, AppKit deriva un tamaño mínimo del contenido
   y la ventana se niega a encogerse.
4. Click-through: `SurfaceHostingView.hitTest` devuelve `nil` fuera de la silueta actual;
   `acceptsFirstMouse = true` para el engranaje.
5. Se pinta **solo la silueta**; el resto del panel es transparente (nada de fondos).

### Geometría

- `NotchGeometryMath` (puro): notch desde `safeAreaInsets.top` + `auxiliaryTopLeft/RightArea`;
  hot zone, zona abierta, rect expandido. Probado sin pantalla.
- `NotchShape`: borde superior **ancho completo** y cuerpo con hombros **cóncavos**
  (`topFlare = 10`), esquinas inferiores convexas (`24`). Es la forma de BoringNotch /
  DynamicNotchKit. No volver a “redondear hacia dentro”.
- `NotchInteractionMachine` (puro): `dormant → armed → open`; el controlador pone los timers.
- `StagePager`: página actual + `offset` de arrastre + `isDragging`. El swipe horizontal
  mueve la página con el dedo; solo durante el gesto se montan las páginas vecinas (los
  widgets de cada página son disjuntos, así que no se duplica ningún `WKWebView`). Al soltar,
  un spring decide: `|offset| > max(40, 22% del ancho)` avanza, si no vuelve. El signo de
  `scrollingDeltaX` se invierte para que deslizar a la izquierda pase página.

### Alto automático

`CorniceSettings.fitToContent` (por defecto **on**): el controlador pide
`WidgetHost.preferredStageHeight(forWidth:)` y suma `chromeHeight = 52`
(14 top + ~16 header + 10 gap + 12 bottom). El alto configurado se ignora mientras esté on.
Si el contenido cambia (montar, redimensionar, reordenar), `host.onLayoutChange` →
`controller.refreshStage()`.

### Etapa sin tarjetas

`WidgetAreaView` pinta los widgets **directamente sobre el negro**, sin relleno ni borde
(regla de DroppyKit: no metas widgets en cards). Separación por espacio: gap de grid 8 pt +
8 pt de padding por celda. No añadir sombras, degradados ni marcos.

---

## 5. Layout

- Grid de 6 columnas. `columns` = span 1–6; `rows` = altura.
- `rowUnit = 30`, `gap = 8`; altura de celda `30r + 8(r−1)`.
- `WidgetGridLayout.layout(widgets:available:)` (puro, testeado) devuelve páginas de frames.
- Los widgets fluyen, hacen wrap y pasan a otra página si la fila no cabe. Los puntos
  reservan 14 pt **solo si hay más de una página**.
- Redimensionado: *Options → Layout*, arrastrando la esquina. `WidgetResize.snapped(...)`
  convierte el delta a celdas (clamp 1–6 × 1–8). Persiste en `widgets.json.sizes`; se
  escribe al soltar, no en cada frame.

---

## 6. Ajustes de la app

`CorniceSettings` (JSON en `~/Library/Application Support/Cornice/settings.json`, envoltorio
`schemaVersion` + `settings`):

| Campo | Uso |
|---|---|
| `motion` | respuesta/rebote de apertura y cierre, retardo y duración del contenido |
| `hoverOpenDelay` / `hoverCloseDelay` | tiempos del hover |
| `expandedWidth` / `expandedHeight` | tamaño; alto ignorado con `fitToContent` |
| `fitToContent` | el panel se ajusta al contenido (default `true`) |
| `showMenuBarIcon` | icono en barra de menús (default `true`; el usuario lo tiene off) |
| `language` | `system` / `en` / `es` |

Reglas:

- Los valores se **clampan** al cargar. Añadir un campo nuevo **siempre** con
  `decodeIfPresent` en `init(from:)`; si no, los archivos viejos rompen y se resetea todo.
- `SettingsStore.set(keyPath:)` persiste con debounce de 250 ms y dispara `onChange`.
- La ventana de Opciones es un sidebar (`NavigationSplitView`) con secciones inyectadas.
  Se reconstruye en cada `show()` y ante cambio de idioma (`SettingsWindowController.refresh`).
- Secciones: General, Movimiento, Interacción, Panel, Disposición, Widgets y una por widget
  con settings declarativos.
- **No** pongas títulos de sección en `CorniceCore`: los construye `AppDelegate.makeSections`
  con `Translator`.

---

## 7. Sistema de widgets

### SDK (`CorniceKit`)

```swift
WidgetManifest(id:name:version:apiVersion:capabilities:networkHosts:keychainServices:
               credentials:settings:placement:refresh:)
```

- `apiVersion` debe ser `1`; el host rechaza manifests con `problems`.
- `Capability`: `.network`, `.keychain`, `.files`, `.calendar`, `.media`, `.notifications`,
  `.tailscale`. **Solo se aplican network, keychain y tailscale.**
- `.network` exige `networkHosts` (hosts o IPs; acepta subdominios).
- `.keychain` exige `keychainServices`; el host entrega `ScopedSecrets`.
- `credentials`: el host inyecta el header (p. ej. `Authorization: Bearer …`) por host.
  El secreto **nunca** llega al widget.
- `settings`: campos declarativos (`toggle`, `number` con min/max, `text`, `select`).
  El host renderiza el formulario, valida/clampa y remonta el widget al cambiar.
- `.tailscale`: `WidgetContext.tailscale` + `cornice.tailscale.status()` /
  `cornice.tailscale.set(bool)`. El host expone **solo** `status`, `up` y `down` del CLI
  (`SystemTailscale`), con timeout; nunca un shell.

`WidgetContext`: `http`, `secrets`, `settings`, `language`, `log`, `availableWidth`,
`capabilities`.

`CorniceWidget`: `makeView()`, `activate()`, `deactivate()`, `tick(Date)`.
`WidgetFactory`: `manifest` + `make(context:)` (instancia, no estático, para widgets de disco).

### Host (`CorniceHost`)

`WidgetHost` es la única autoridad:

- Descubre built-ins (hoy ninguno) + `.cornicewidget` en Application Support.
- `catalog` (con `enabled`, `size`, `settings`), `widgets` montados.
- Un **único ticker de 1 s** y **solo** con la superficie abierta (`setActive`).
- `setEnabled`, `move(before:)`, `setSize`, `persistSize`, `resetSizes`, `reload`.
- `setLanguage` **remonta** los widgets para que el web reciba el nuevo `cornice.language`.
- Preferencias en `widgets.json`:
  `enabledDiskWidgets`, `disabledDiskWidgets` (los de disco empiezan off salvo
  `defaultEnabled`), `disabledBuiltIns`, `order`, `sizes`.

### Ciclo de vida

1. `start()` → `reload()` → monta los habilitados y los `activate()` si está activo.
2. Abrir/cerrar la superficie → `setActive(true/false)` → `activate/deactivate` + ticker.
3. Tick cada segundo → `widget.tick(now)` (para countdowns, no para fetch ciego).
4. `deactivate` no borra datos: al reabrir se refresca si toca.

---

## 8. Widgets desde disco

Formato: `~/Library/Application Support/Cornice/Widgets/<Nombre>.cornicewidget/`

```
manifest.json
index.html
```

```json
{
  "id": "com.example.status",
  "name": "Status",
  "version": "1.3.0",
  "apiVersion": 1,
  "capabilities": ["network"],
  "networkHosts": ["192.0.2.10"],
  "keychainServices": [],
  "credentials": [],
  "settings": [
    { "id": "refreshSeconds", "title": "Refresh every", "type": "number",
      "min": 10, "max": 300, "step": 5, "default": 30 }
  ],
  "placement": { "columns": 3, "rows": 3 },
  "refresh": { "interval": 30 },
  "entry": "index.html",
  "defaultEnabled": true
}
```

Validación (`WidgetBundleStore.load`): manifiesto presente y decodificable, semver,
`apiVersion`, capacidades conocidas, hosts/servicios coherentes, `entry` **dentro** del
bundle (componentes de ruta, no `hasPrefix`; ojo `/var` vs `/private/var`) y existente.

### Sandbox web

`WKWebView` con `websiteDataStore = .nonPersistent()`, navegación confinada al bundle,
sin Keychain, sin archivos, sin `URLSession`. Puente:

```js
await cornice.fetch(url, { method, headers }); // { status, text }
cornice.onTick(ts => {});
cornice.settings;   // objeto con los valores
cornice.language;   // "en" | "es"
cornice.locale;     // "en_GB" | "es_ES"
await cornice.tailscale.status();  // { status: { backendState, ip, peersOnline, … } }
await cornice.tailscale.set(true); // up / down
```

El `fetch` pasa por `WidgetHTTPClient` (allow-list + 30 req/min + credenciales inyectadas).
Un widget **nunca** debe hablar con el sistema por su cuenta.

### Instalación y upgrades

`WidgetInstaller.installBundledWidgets` copia los bundles de `Contents/Resources/Widgets`
solo si faltan o si la **versión es mayor**. Para publicar un cambio en un widget incluido:
**sube la versión en su manifest**; si no, la copia instalada no se toca (es intencional:
nunca se pisan carpetas del usuario).

---

## 9. Widgets incluidos

| id | Nombre | Ver | Tamaño | Capacidades | Notas |
|---|---|---|---|---|---|
| `com.example.status` | Example Widget | 2.4.0 | 3×3 | network, keychain | fetch a `example.com`; credencial `Authorization: Bearer` desde `com.duque.cornice/opencode-api-key` |
| `com.example.status` | Status | 1.3.0 | 3×3 | network | `http://192.0.2.10:8123/api/overview`; 4 barras (CPU/RAM/Disco/Backup), guests, temp, WiFi, tráfico |
| `com.duque.clock` | Clock | 1.3.0 | 6×2 | — | demo; `defaultEnabled: false`; usa `cornice.locale` |
| `com.duque.tailscale` | Tailscale | 1.3.0 | 6×2 | tailscale | switch de conexión + IP/peers; CLI `/usr/local/bin/tailscale` (app Store) |

Todos en `BundledWidgets/`. Los HTML llevan diccionario EN/ES inline (`const ES = ...`).

---

## 10. Secretos

`FileSecretStore`: un archivo por `service/account` bajo
`~/Library/Application Support/Cornice/secrets/`, permisos `0600`.

**Por qué no el Llavero**: las builds ad-hoc cambian de firma en cada rebuild y macOS
vuelve a pedir permiso (llegó a bloquear el arranque). El modelo de amenaza es el mismo que
el archivo plano que ya existía (`~/.config/example-usage/key`), y el widget sigue sin
poder leerlo: solo el host inyecta la credencial.

`LegacyCredentials.migrateLegacyKeyIfNeeded()` importa la key legacy al arrancar.

---

## 11. Localización

- `AppLanguage` (`system`/`en`/`es`) + `Translator(language)("English", "Español")` en Core.
  Sin `.strings` ni bundles de recursos: el cambio es en caliente.
- SDK: `WidgetLanguage.en/.es` en `WidgetContext.language`.
- Web: `cornice.language` / `cornice.locale`.
- Cambiar idioma: `settings.onChange` → `host.setLanguage` (remonta widgets) +
  `settingsWindow.refresh()` (reconstruye sidebar/título).
- Los títulos del sidebar viven en `AppDelegate.makeSections`, no en Core.
- Nombres de producto (“Example Widget”, “Status”) no se traducen.

---

## 12. Tests

```bash
swift test
```

87 tests. Cobertura por área:

- Geometría del notch y zonas (puro).
- Máquina de estados del hover.
- Pager: arrastre, rubber-band en los extremos, commit/cancel.
- Ajustes: clamp, round-trip, archivo corrupto, claves ausentes.
- Grid: filas, páginas, prioridad, límites.
- Orden y tamaños: `WidgetOrdering`, `WidgetResize`, persistencia.
- Loader de disco: válido, apiVersion, capacidad desconocida, traversal, entry ausente.
- Instalador: copia, upgrade por versión, no pisar misma versión.
- Capabilities: allow-list, rate limit, scope de secretos, inyección de credenciales.
- Contrato de manifiesto y `HTTPResponse`.
- Bundled widgets: todos cargan.
- Idioma: translator, persistencia, remontaje.

Snapshots (a `$CORNICE_SNAPSHOT_DIR`): superficie, filmstrip de transición, formulario.

Al añadir un widget incluido, añade/actualiza su test de carga (ya hay uno que recorre
`BundledWidgets/`).

---

## 13. Verificar visualmente

La UI vive en una ventana sin key window; para revisarla, captura por región:

```bash
./scripts/screenshot.sh 27 /tmp/panel.png     # panel del notch (layer 27)
./scripts/screenshot.sh 0 /tmp/opciones.png   # ventana de Opciones (layer 0)
```

Usa `screencapture -R` sobre los bounds de `CGWindowList`. Requiere permiso de grabación de
pantalla. Si el panel no aparece, comprueba que no está dormido: lánzalo con
`CORNICE_START_OPEN=1` (pinea) y **sin** el agente cargado.

Para ver datos reales de los widgets, abre la superficie (hover o `START_OPEN`) y espera
al primer tick (1 s).

---

## 14. Gotchas (lista viva)

| Síntoma | Causa / arreglo |
|---|---|
| Rectángulo negro al cambiar de espacio | ventana transparente visible al hacer snapshot → `orderOut` en reposo |
| El panel no encoge | `NSHostingView.sizingOptions` derivando tamaño mínimo → `[]` |
| La apertura “no es uniforme” | contenido refloweando dentro del frame animado → tamaño fijo + máscara + fade al final |
| Se ve el contenido antes que la silueta | falta el delado del fade o el frame final no está puesto antes de cambiar el estado |
| Doble instancia / captura vieja | `pkill` con KeepAlive → `launchctl bootout` antes de probar `dist/` |
| El icono de menú no desaparece | el setting se escribió fuera de `settings` en el JSON |
| `entry` rechazado estando dentro | comparación de paths con `/var` vs `/private/var` → `PathContainment` por componentes |
| Widget de disco no se actualiza | no subiste `version` en su manifest |
| Cambio de idioma no llega a widgets | `setLanguage` debe remontar; no basta con asignar |
| Prompt del Llavero en cada build | firma ad-hoc → secretos en archivo 0600, no Keychain |
| LAN inaccesible | falta `NSLocalNetworkUsageDescription` / `NSAllowsLocalNetworking`; o no estás en la tailnet |
| La página web se queda con el ancho viejo | devolver el `WKWebView` directo a SwiftUI no reflowea al redimensionar → contenedor con Auto Layout en `WebWidgetView` |
| Cambias un HTML y no se ve | no subiste `version` en el manifest; el instalador solo actualiza versiones mayores |

---

## 15. Añadir un widget (checklist)

1. Crea `BundledWidgets/<Nombre>.cornicewidget/{manifest.json,index.html}`.
2. `id` reverse-DNS único; `apiVersion: 1`; `version` semver.
3. Declara solo las capacidades que uses, con sus listas (`networkHosts`,
   `keychainServices`, `credentials`).
4. Si es first-party y debe venir activo: `defaultEnabled: true`.
5. Usa `cornice.settings` para opciones y `cornice.language` para textos.
6. No metas el contenido en una tarjeta: el fondo es el panel.
7. Sube la versión si ya existía.
8. `swift test` (el test de bundles lo carga) y captura con `scripts/screenshot.sh`.
9. Actualiza `README.md` (sección del widget) y, si cambia el contrato, este archivo.

---

## 16. Convenciones

- **Commits**: conventional commits (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`,
  `chore:`). Rama `main` mientras no haya remoto; si el repo crece, `feature/<nombre>`.
- **Código y UI en inglés**; documentación de trabajo (este archivo) y conversación en español.
- Swift 6 estricto: `@MainActor` en todo lo que toca UI/AppKit; lógica pura separada y
  testeada. Nada de `@unchecked Sendable` salvo justificación.
- No añadir dependencias externas.
- Comentarios solo para lo no obvio (por qué, no qué).
- Si cambias comportamiento visible, actualiza `README.md` y, si es un invariante, este
  archivo.

---

## 17. Roadmap / pendientes

- UI de credenciales para pegar la API key sin depender del archivo legacy.
- Bundles **nativos** Swift con firma (hoy solo HTML/JS).
- Fila que rodea la cámara (estilo Droppy) y composiciones solo/pareado.
- Más widgets del homelab: acestream (usa credencial por header), servicios `example.com`,
  F1, Home Assistant.
- Swipe entre páginas ya existe; valorar transición animada entre páginas.
- `speedtest`, `loadAvg` y `uptime` del dashboard aún no se muestran (no caben en 3×3).
