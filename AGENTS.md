# AGENTS.md — Cornice

Contrato para agentes que trabajen en este repo. Léelo entero antes de tocar código.
Si algo aquí contradice al código, **gana el código**: corrige este documento en el mismo
commit.

Documentación de producto: `README.md` (en inglés, como la UI). Este archivo está en
español porque es la nota de trabajo.

---

## 1. Qué es Cornice

Host modular para el notch del MacBook, orientado a **desarrolladores y homelabs**. El notch
es una superficie donde se montan widgets; los widgets son bundles HTML/JS que se cargan
desde disco, declaran capacidades y nunca tocan el sistema directamente.

- **App**: `Cornice.app` (accesoria, sin Dock; icono de barra opcional).
- **SDK**: `CorniceKit` — manifiesto, capacidades, settings, contexto, `CorniceWidget`.
- **Host**: `CorniceHost` — montaje, reloj, capacidades, secretos, loader de disco, UI de ajustes.
- **Core**: `CorniceCore` — panel, geometría, animación, ajustes, localización.

Estado: M11. 91 tests. Pensado para instalarse desde el repo (`./install.sh`), no para la
App Store.

> Si una tarea toca el homelab, aplica también `~/.config/opencode/AGENTS.md` y el repo
> `~/homeserver` (pull antes, nota después).

---

## 2. Privacidad (leer antes de escribir docs)

**Los widgets first-party de este repo son personales.** No documentes, nombres ni describas
en `README.md`, en este archivo, en commits o en notas públicas:

- sus nombres o IDs,
- sus endpoints, hosts o IPs,
- sus credenciales o servicios de secretos,
- capturas de su UI.

Si necesitas contexto para mantenerlos, lee su `manifest.json` y su código. Al escribir
documentación usa ejemplos neutros (`com.example.*`, `example.com`, `192.0.2.10`). Esta regla
aplica también a los mensajes de commit.

---

## 3. Mapa del repo

```
Sources/
  CorniceKit/        SDK: sin AppKit, sin Core, sin red propia
  CorniceCore/       panel, geometría, estado, ajustes, shell de Opciones
  CorniceHost/       host de widgets, loader de disco, sandbox web, UI de widgets
  CorniceApp/        @main, AppDelegate, composición de secciones
BundledWidgets/      bundles que viajan dentro de la app (contenido personal; ver §2)
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

## 4. Build, test, install

```bash
swift build                      # debug
swift test                       # 91 tests
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

## 5. La superficie (CorniceCore)

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

### Paginación

`StagePager`: página actual + `offset` de arrastre + `isDragging`.

- El swipe horizontal mueve la página con el dedo. `drag(by:)` recibe `scrollingDeltaX`
  **sin invertir** (dedo a la izquierda ⇒ delta negativo ⇒ offset negativo ⇒ página
  siguiente). No reintroduzcas una negación: ya hubo dos bugs por eso.
- Solo durante el gesto se montan las páginas vecinas (`visiblePages`). Los widgets de cada
  página son disjuntos, así que no se duplica ningún `WKWebView`.
- Al soltar, spring: si `|offset| > max(40, 22 % del ancho)` avanza; si no, vuelve.
  `isDragging` se mantiene 380 ms para que la animación termine.
- Momentum: se espera a `momentumPhase == .ended`; fallback de 0,18 s al levantar el dedo.
  Rueda de ratón (sin fases): debounce de 0,16 s.

### Alto automático

`CorniceSettings.fitToContent` (default **on**): el controlador pide
`WidgetHost.preferredStageHeight(forWidth:)` y suma `chromeHeight = 52`
(14 top + ~16 header + 10 gap + 12 bottom). El alto configurado se ignora mientras esté on.
Si el contenido cambia, `host.onLayoutChange` → `controller.refreshStage()`.

### Etapa sin tarjetas

`WidgetAreaView` pinta los widgets **directamente sobre el negro**, sin relleno ni borde
(regla de DroppyKit: no metas widgets en cards). Separación por espacio: gap de grid 8 pt +
8 pt de padding por celda. No añadir sombras, degradados ni marcos.

---

## 6. Layout

- Grid de 6 columnas. `columns` = span 1–6; `rows` = altura.
- `rowUnit = 30`, `gap = 8`; altura de celda `30r + 8(r−1)`.
- `WidgetGridLayout.layout(widgets:available:)` (puro, testeado) devuelve páginas de frames.
- Los widgets fluyen, hacen wrap y pasan a otra página si la fila no cabe. Los puntos
  reservan 14 pt **solo si hay más de una página**.
- Redimensionado: *Options → Layout*, arrastrando la esquina. `WidgetResize.snapped(...)`
  convierte el delta a celdas (clamp 1–6 × 1–8). Persiste en `widgets.json.sizes`; se
  escribe al soltar, no en cada frame.
- Con `fitToContent` on y poco contenido, todo cabe en una página: no hay swipe que probar.
  Para QA de paginación, desactiva el ajuste y baja la altura.

---

## 7. Ajustes de la app

`CorniceSettings` (JSON en `~/Library/Application Support/Cornice/settings.json`, envoltorio
`schemaVersion` + `settings`):

| Campo | Uso |
|---|---|
| `motion` | respuesta/rebote de apertura y cierre, retardo y duración del contenido |
| `hoverOpenDelay` / `hoverCloseDelay` | tiempos del hover |
| `expandedWidth` / `expandedHeight` | tamaño; alto ignorado con `fitToContent` |
| `fitToContent` | el panel se ajusta al contenido (default `true`) |
| `showMenuBarIcon` | icono en barra de menús (default `true`) |
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

## 8. Sistema de widgets

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

`WidgetContext`: `http`, `secrets`, `settings`, `language`, `tailscale`, `log`,
`availableWidth`, `capabilities`.

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

## 9. Widgets desde disco

Formato: `~/Library/Application Support/Cornice/Widgets/<Nombre>.cornicewidget/`

```
manifest.json
index.html
```

```json
{
  "id": "com.example.status",
  "name": "Status",
  "version": "1.0.0",
  "apiVersion": 1,
  "capabilities": ["network"],
  "networkHosts": ["status.example.com"],
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
await cornice.tailscale.status();
await cornice.tailscale.set(true);
```

El `fetch` pasa por `WidgetHTTPClient` (allow-list + 30 req/min + credenciales inyectadas).
Un widget **nunca** debe hablar con el sistema por su cuenta.

`WebWidgetView` envuelve el `WKWebView` en un `NSView` con Auto Layout: devolverlo directo a
SwiftUI no reflowea la página al cambiar el tamaño de la celda.

### Instalación y upgrades

`WidgetInstaller.installBundledWidgets` copia los bundles de `Contents/Resources/Widgets`
solo si faltan o si la **versión es mayor**. Para publicar un cambio en un widget incluido:
**sube la versión en su manifest**; si no, la copia instalada no se toca (es intencional:
nunca se pisan carpetas del usuario).

---

## 10. Widgets incluidos

Los bundles de `BundledWidgets/` son **personales**: no se documentan aquí ni en el README
(§2). Su manifest es la fuente de verdad. Si trabajas en uno, no publiques sus endpoints,
IDs, credenciales ni capturas.

El host ignora manifests con `problems`; el test `testEveryBundledWidgetLoads` recorre la
carpeta y falla si alguno es inválido.

---

## 11. Secretos

`FileSecretStore`: un archivo por `service/account` bajo
`~/Library/Application Support/Cornice/secrets/`, permisos `0600`.

**Por qué no el Llavero**: las builds ad-hoc cambian de firma en cada rebuild y macOS
vuelve a pedir permiso (llegó a bloquear el arranque). El modelo de amenaza es el mismo que
el de un archivo plano de usuario, y el widget sigue sin poder leerlo: solo el host inyecta
la credencial al hacer `fetch`.

Hay un migrador de credenciales legacy en el host; no documentes de dónde lee.

---

## 12. Localización

- `AppLanguage` (`system`/`en`/`es`) + `Translator(language)("English", "Español")` en Core.
  Sin `.strings` ni bundles de recursos: el cambio es en caliente.
- SDK: `WidgetLanguage.en/.es` en `WidgetContext.language`.
- Web: `cornice.language` / `cornice.locale`.
- Cambiar idioma: `settings.onChange` → `host.setLanguage` (remonta widgets) +
  `settingsWindow.refresh()` (reconstruye sidebar/título).
- Los títulos del sidebar viven en `AppDelegate.makeSections`, no en Core.
- Los nombres de producto de los widgets personales no se traducen ni se documentan.

---

## 13. Tests

```bash
swift test
```

91 tests. Cobertura por área:

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

---

## 14. Verificar visualmente

La UI vive en una ventana sin key window; para revisarla, captura por región:

```bash
./scripts/screenshot.sh 27 /tmp/panel.png     # panel del notch (layer 27)
./scripts/screenshot.sh 0 /tmp/opciones.png   # ventana de Opciones (layer 0)
```

Usa `screencapture -R` sobre los bounds de `CGWindowList`. Requiere permiso de grabación de
pantalla. Si el panel no aparece, comprueba que no está dormido: lánzalo con
`CORNICE_START_OPEN=1` (pinea) y **sin** el agente cargado.

Las capturas son para revisión local: **no** las subas al repo ni las enseñes en docs
públicas si contienen widgets personales (§2).

---

## 15. Gotchas (lista viva)

| Síntoma | Causa / arreglo |
|---|---|
| Rectángulo negro al cambiar de espacio | ventana transparente visible al hacer snapshot → `orderOut` en reposo |
| El panel no encoge | `NSHostingView.sizingOptions` derivando tamaño mínimo → `[]` |
| La apertura “no es uniforme” | contenido refloweando dentro del frame animado → tamaño fijo + máscara + fade al final |
| Se ve el contenido antes que la silueta | falta el delay del fade o el frame final no está puesto antes de cambiar el estado |
| Doble instancia / captura vieja | `pkill` con KeepAlive → `launchctl bootout` antes de probar `dist/` |
| El icono de menú no desaparece | el setting se escribió fuera de `settings` en el JSON |
| `entry` rechazado estando dentro | comparación de paths con `/var` vs `/private/var` → `PathContainment` por componentes |
| Widget de disco no se actualiza | no subiste `version` en su manifest |
| Cambio de idioma no llega a widgets | `setLanguage` debe remontar; no basta con asignar |
| Prompt del Llavero en cada build | firma ad-hoc → secretos en archivo 0600, no Keychain |
| LAN inaccesible | falta `NSLocalNetworkUsageDescription` / `NSAllowsLocalNetworking`, o no estás en la VPN |
| La página web se queda con el ancho viejo | devolver el `WKWebView` directo a SwiftUI no reflowea → contenedor con Auto Layout |
| El swipe va al revés | doble inversión de `scrollingDeltaX`: el offset usa el mismo signo que el delta |
| Cambias un HTML y no se ve | no subiste `version` en el manifest |

---

## 16. Añadir un widget

1. Crea `BundledWidgets/<Nombre>.cornicewidget/{manifest.json,index.html}`.
2. `id` reverse-DNS único; `apiVersion: 1`; `version` semver.
3. Declara solo las capacidades que uses, con sus listas (`networkHosts`,
   `keychainServices`, `credentials`).
4. Si debe venir activo: `defaultEnabled: true`.
5. Usa `cornice.settings` para opciones y `cornice.language` para textos.
6. No metas el contenido en una tarjeta: el fondo es el panel.
7. Sube la versión si ya existía.
8. `swift test` (el test de bundles lo carga) y captura local con `scripts/screenshot.sh`.
9. **No** lo documentes en `README.md` si es personal (§2). Si es genérico, añade una sección
   y actualiza este archivo si cambia el contrato.

---

## 17. Convenciones

- **Commits**: conventional commits (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`,
  `chore:`), sin nombres, hosts ni datos de widgets personales. Rama `main` mientras no haya
  remoto; si el repo crece, `feature/<nombre>`.
- **Código y UI en inglés**; documentación de trabajo (este archivo) y conversación en español.
- Swift 6 estricto: `@MainActor` en todo lo que toca UI/AppKit; lógica pura separada y
  testeada. Nada de `@unchecked Sendable` salvo justificación.
- No añadir dependencias externas.
- Comentarios solo para lo no obvio (por qué, no qué).
- Si cambias comportamiento visible, actualiza `README.md` y, si es un invariante, este
  archivo.

---

## 18. Roadmap / pendientes

- UI de credenciales para pegar tokens sin depender de migraciones legacy.
- Bundles **nativos** Swift con firma (hoy solo HTML/JS).
- Fila que rodea la cámara (estilo Droppy) y composiciones solo/pareado.
- Contrato de **acciones** en el SDK (hacer, no solo mostrar) con capacidades.
- Tooling de autoría: `cornice new` / `cornice dev` con recarga en caliente.
- Más integraciones de infraestructura (servicios self-hosted, CI/PRs, contenedores, red).
