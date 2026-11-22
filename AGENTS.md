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

Estado: M11. 136 tests. Pensado para instalarse desde el repo (`./install.sh`), no para la
App Store.

> Si una tarea toca el homelab, aplica también las reglas globales
> (`~/.config/opencode/AGENTS.md`) y el repo de conocimiento del homelab (pull antes, nota
> después).

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
BundledWidgets/      solo el widget de ejemplo genérico
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
swift test                       # 136 tests
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
| `CORNICE_START_STORAGE=1` | Abre la ventana de Almacenamiento al arrancar |
| `CORNICE_START_PAGE=N` | Selecciona la página N al arrancar (QA de composición) |

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
- **Rueda de ratón** (sin fase ni momentum): no usa el modelo de arrastre. Se acumula el
  delta del eje dominante (`WheelPagingState`: 10 pt por línea, umbral 20 pt) y cada notch
  avanza **una** página, con 0,30 s de enfriamiento y reset tras 0,40 s de inactividad.
  Así una rueda lenta no se queda a medias y una rápida no salta tres páginas.
  Ojo: `NSEvent.Phase` es un `OptionSet`; `phase == .none` compara con `Optional.none` y
  **siempre es false**. Usa `phase.isEmpty`.

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
- `rowUnit = 30`, `gap = 8`; altura de celda `30r + 8(r−1)`. `layout(..., scale:)` multiplica
  filas y separaciones por `uiScale`.
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
| `uiScale` | escala de texto/celdas (0.85–1.5); 1.15–1.25 en pantallas 1x |

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
  `.tailscale`, `.storage`, `.speedtest`. **Solo se aplican network, keychain, tailscale,
  storage y speedtest.**
- `.network` exige `networkHosts` (hosts o IPs; acepta subdominios). Respuestas limitadas a
  2 MB (`maxResponseBytes`) y leídas en streaming.
- `.keychain` exige `keychainServices`; el host entrega `ScopedSecrets`.
- `credentials`: el host inyecta el header (p. ej. `Authorization: Bearer …`) solo para el
  **host exacto** de la regla: un subdominio no hereda la credencial. El secreto **nunca**
  llega al widget.
- `settings`: campos declarativos (`toggle`, `number` con min/max, `text`, `select`).
  El host renderiza el formulario, valida/clampa y remonta el widget al cambiar.
- `.tailscale`: `WidgetContext.tailscale` + `cornice.tailscale.status()` /
  `cornice.tailscale.set(bool)`. El host expone **solo** `status`, `up` y `down` del CLI
  (`SystemTailscale`), con timeout; nunca un shell.
- `.speedtest`: `WidgetContext.speedtest` + `cornice.speedtest.run(segundos)` /
  `last()` / `cancel()` / `onProgress(cb)`. Un solo binario (`/usr/bin/networkQuality`) con
  flags fijos; la duración la clampa el host (3–30 s por fase).

`SystemTailscale` solo ejecuta binarios **de confianza**: owner root o el usuario actual y
sin permiso de escritura para grupo/otros. Prefiere el binario de la app (`/Applications/…`)
al wrapper de `/usr/local/bin` y al de Homebrew.

El binario se resuelve **en cada llamada** (no en `init`): si Tailscale se instala o se
actualiza con la app abierta, la siguiente consulta lo encuentra. `status` reintenta una vez
a los 250 ms (daemon reiniciándose). La salida va a **archivos temporales**, no a un pipe:
evita el bloqueo cuando el JSON supera el buffer y, sobre todo, que un aviso por stderr
contamine el JSON. Al vencer el timeout se escala a `SIGTERM` → `SIGKILL`: un CLI colgado
que sobrevive deja el canal con la GUI/extension atascado y **todas** las llamadas
posteriores fallan con “The Tailscale GUI failed to start”.

`statusDetailed()` conserva el motivo (el protocolo tiene una implementación por defecto
que devuelve `.unavailable`). El CLI puede salir con código 0 y texto en vez de JSON; eso
se reporta como `.commandFailed` y el widget distingue “CLI no disponible” de
“Tailscale no responde”.

**El CLI se lanza a través de `/usr/bin/osascript` (`do shell script`)**, no con `Process`
directo. Un hijo directo de un LaunchAgent se queda colgado en
`LSSetApplicationInformationItem` (LaunchServices) al intentar hablar con la GUI de
Tailscale: `tailscale status` funciona en Terminal pero el widget dice “no responde”. Con
`do shell script` el comando corre en un contexto donde LaunchServices responde. No lo
“simplifiques” a `Process`: ya se probó y se cuelga.

`SystemSpeedTest` ejecuta `/usr/bin/networkQuality` en **dos procesos**, uno por dirección:
`-u` significa “no subas” (solo descarga) y `-d` “no bajes” (solo subida); los flags están
invertidos respecto al nombre. Se hace así para poder pintar la bajada mientras corre la
subida. La duración se clampa a 3–30 s por fase, solo hay una prueba a la vez (`.busy`) y
`cancel()` mata el proceso. El binario pasa por el mismo chequeo `TrustedExecutable` que el
CLI de Tailscale. El último informe se guarda en `speedtest.json`: el webview es efímero y
sin eso el widget perdería las cifras al remontarse. La salida va a archivos temporales
(el JSON lleva arrays de muestras y llenaría un pipe).

`WidgetContext`: `http`, `secrets`, `settings`, `language`, `tailscale`, `storage`,
`speedtest`, `log`, `availableWidth`, `capabilities`.

`CorniceWidget`: `makeView()`, `activate()`, `deactivate()`, `tick(Date)`.
`WidgetFactory`: `manifest` + `make(context:)` (instancia, no estático, para widgets de disco).

### Host (`CorniceHost`)

`WidgetHost` es la única autoridad:

- Descubre built-ins (hoy ninguno) + `.cornicewidget` en Application Support.
- `catalog` (con `enabled`, `size`, `settings`), `widgets` montados.
- Un **único ticker de 1 s** y **solo** con la superficie abierta (`setActive`).
- `setEnabled`, `move(before:)`, `setSize`, `persistSize`, `resetSizes`, `reload`.
- `setLanguage` **remonta** los widgets para que el web reciba el nuevo `cornice.language`.
- Los bundles de disco con `id` duplicado se rechazan (gana el primero por orden
  alfabético; el segundo aparece en `discoveryErrors`).
- Las redirecciones pasan por `WidgetRedirectGuard`: host fuera de la allow-list → cancelada;
  cambio de host → se quitan credenciales y cookies.
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
Además se recorre el bundle y se rechazan **symlinks y archivos especiales** (WebKit tiene
permiso de lectura sobre todo el directorio; un symlink podría apuntar a `~/.ssh`).

### Sandbox web

`WKWebView` con `websiteDataStore = .nonPersistent()`, navegación confinada al bundle,
sin Keychain, sin archivos, sin `URLSession`.

**Escala y tipografía**: `uiScale` multiplica las celdas del grid y se aplica como
`pageZoom` al webview. Ojo: `pageZoom` puesto antes de `loadFileURL` **se resetea**; se
aplica en `didFinish`.

El host inyecta una única escala tipográfica como variables CSS (`WidgetTypography`), en
`:root` **antes** del HTML: título 12/600, etiqueta 10/500 al 58 %, valor 16/600 tabular,
meta 9,5/500 al 40 %, mono 9,5 al 42 %. Los widgets **no** declaran tamaños propios; mono
solo para datos alineados (tasas, contadores, IPs). `uiScale` es el único multiplicador.

En pantallas 1x el host añade `html.cornice-low-dpi` (solo para forzar
`-webkit-font-smoothing: auto`, el `antialiased` adelgaza en 1x) y expone
`cornice.pixelRatio`. No vuelvas a escalar tipografía por display: se hacía antes y se
eliminó por dos motivos (dos escalados superpuestos y deriva entre widgets).

**Lockdown de red**: `WidgetContentRules` compila un `WKContentRuleList` que bloquea
`^https?://`, `^wss?://` y `^ftp://`. Sin él, la página podría usar `fetch`, `<img>` o
`<script src>` contra cualquier host y saltarse las capacidades (incluido exfiltrar settings
o cargar código remoto con acceso al bridge). Si la compilación falla, el widget **no se
carga** (fail closed). `cornice.fetch` es nativo y no pasa por WebKit, así que sigue
funcionando.

**Redirecciones**: `WidgetRedirectGuard` (delegate de `URLSession`) cancela cualquier
redirección a un host fuera de la allow-list y, si cambia de host, elimina las cabeceras de
credenciales y cookies. El cliente usa una sesión `ephemeral` sin cookies ni caché; un 3xx
que llegue a `send` se trata como error.

Puente:

```js
await cornice.fetch(url, { method, headers }); // { status, text }
cornice.onTick(ts => {});
cornice.settings;   // objeto con los valores
cornice.language;   // "en" | "es"
cornice.locale;     // "en_GB" | "es_ES"
await cornice.tailscale.status();
await cornice.tailscale.set(true);
await cornice.storage.status();   // totalBytes, freeBytes, usedBytes, recoverableBytes
await cornice.storage.review();   // abre la ventana nativa de revisión
await cornice.speedtest.run(8);   // { status: { download, upload, … } }
await cornice.speedtest.last();   // { status: informe | null }
cornice.speedtest.onProgress(({ phase, measurement }) => {});
await cornice.speedtest.cancel();
```

El `fetch` pasa por `WidgetHTTPClient` (allow-list + 30 req/min + credenciales inyectadas).
Un widget **nunca** debe hablar con el sistema por su cuenta.

### Almacenamiento

`SystemStorage` (actor) expone la capability `.storage`. El SDK solo permite
`status()` (capacidad + recuperable cacheado 10 min) y `review()`, que publica
`.corniceShowStorage`; `AppDelegate` abre `StorageWindowController` (también accesible desde
Opciones → Almacenamiento y el menú de barra).

`StorageCatalog` define raíces **fijas** bajo el home: cachés de apps/Apple, logs,
DerivedData, iOS DeviceSupport, cachés de simulador, npm/Cargo/Gradle/Maven, cachés de
contenedores, Papelera y copias de iPhone. `StorageScanner` mide con `/usr/bin/du -sk`
(lectura, sin shell) y `StorageCleaner` borra hijos de esas raíces con FileManager, sin
seguir symlinks y comprobando contención. La ventana separa recomendado/avanzado; Papelera y
copias son opt-in y piden confirmación. Nunca toca Documentos, Fotos, Mail, Application
Support, datos de contenedores, `/Library/Caches` ni snapshots de Time Machine. La pestaña
Analizar lista archivos grandes y descargas antiguas y solo los mueve a la Papelera.

Debug: `CORNICE_START_STORAGE=1` abre la ventana al arrancar.

`WebWidgetView` envuelve el `WKWebView` en un `NSView` con Auto Layout: devolverlo directo a
SwiftUI no reflowea la página al cambiar el tamaño de la celda.

### Test de velocidad

`SystemSpeedTest` (actor) expone la capability `.speedtest`. `run(duration:progress:)`
lanza dos procesos de `/usr/bin/networkQuality` (descarga y subida) y emite
`.phase` / `.measured` para que el widget pinte la bajada mientras sube. `last()` lee
`speedtest.json` y `cancel()` mata el proceso en curso. El test es manual por diseño: mueve
cientos de MB y no debe dispararse al abrir el panel.

`WebWidgetContent` publica el progreso con `window.__corniceSpeedTestProgress(payload)`; el
widget se suscribe con `cornice.speedtest.onProgress(cb)`. Las respuestas usan la misma
convención que storage/tailscale: el objeto viaja en `status` del payload resuelto.

### Instalación y upgrades

`WidgetInstaller.installBundledWidgets` copia los bundles de `Contents/Resources/Widgets`
solo si faltan o si la **versión es mayor**. Para publicar un cambio en un widget incluido:
**sube la versión en su manifest**; si no, la copia instalada no se toca (es intencional:
nunca se pisan carpetas del usuario).

---

## 10. Widgets incluidos

`BundledWidgets/` contiene **solo un widget de ejemplo genérico** (Clock). Los widgets
personales viven fuera del repo, en una carpeta local de bundles, y se instalan a mano en
`~/Library/Application Support/Cornice/Widgets/`. No los traigas al repo ni los documentes
(§2).

El host ignora manifests con `problems`; el test `testEveryBundledWidgetLoads` recorre la
carpeta y falla si alguno es inválido.

---

## 11. Secretos

`FileSecretStore`: un archivo por `service/account` bajo
`~/Library/Application Support/Cornice/secrets/`, creado con `0600` desde el inicio y en
directorios `0700`.

**Por qué no el Llavero**: las builds ad-hoc cambian de firma en cada rebuild y macOS
vuelve a pedir permiso (llegó a bloquear el arranque). El modelo de amenaza es el mismo que
el de un archivo plano de usuario, y el widget sigue sin poder leerlo: solo el host inyecta
la credencial al hacer `fetch`.

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

136 tests. Cobertura por área:

- Geometría del notch y zonas (puro).
- Máquina de estados del hover.
- Pager: arrastre, rubber-band en los extremos, commit/cancel.
- Rueda: acumulación por notch, dirección, enfriamiento y reset por inactividad.
- Ajustes: clamp, round-trip, archivo corrupto, claves ausentes.
- Grid: filas, páginas, prioridad, límites.
- Orden y tamaños: `WidgetOrdering`, `WidgetResize`, persistencia.
- Loader de disco: válido, apiVersion, capacidad desconocida, traversal, entry ausente.
- Instalador: copia, upgrade por versión, no pisar misma versión.
- Capabilities: allow-list, rate limit, scope de secretos, inyección de credenciales.
- Seguridad web: reglas de red (JSON), política de redirecciones (host y cabeceras) y
  límite de tamaño de respuesta.
- Seguridad de rutas: claves de settings sin colisión y IDs duplicados rechazados.
- Contrato de manifiesto y `HTTPResponse`.
- Bundled widgets: todos cargan y usan los tokens de `WidgetTypography`.
- Tipografía: tokens del host (`WidgetTypographyTests`).
- Almacenamiento: filtros de categorías, contención y borrado en directorios temporales
  (`StorageTests`).
- Test de velocidad: parser de las dos generaciones de claves, clamp de duración, single-flight,
  cancelación, timeout, persistencia del último informe y gating por capacidad.
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
| Un widget no carga y el log dice “content rules unavailable” | falló la compilación del `WKContentRuleList`; se falla cerrado a propósito |
| Un widget intenta `fetch()` directo y no funciona | correcto: solo `cornice.fetch`; el resto lo bloquea el content rule list |
| Se ve borroso en un monitor 1x | densidad física (~109 ppi) → subir `uiScale` a 1.15–1.25; la tipografía ya sale de `WidgetTypography` |
| El zoom no se aplica | `pageZoom` se resetea al navegar: aplicarlo en `didFinish` |
| Un bundle se rechaza por “link or special file” | contiene un symlink; WebKit tendría lectura fuera del bundle |
| Tailscale deja de responder tras mover el binario | solo se ejecutan binarios root/usuario sin escritura de grupo; revisa owner y permisos |
| “CLI de Tailscale no disponible” con el CLI funcionando | stderr mezclado con el JSON, binario cacheado en `init` o un CLI colgado que atasca el canal GUI↔extensión; el host ya separa salidas, resuelve por llamada y mata el proceso a los 6 s. Si persiste, reinicia Tailscale (el CLI desde Terminal debe devolver JSON) |
| `tailscale status` funciona en Terminal pero el widget dice “no responde” | el hijo directo de un LaunchAgent se cuelga en LaunchServices; el host lo ejecuta vía `osascript` + `do shell script` |
| `networkQuality -u` sube en vez de bajar | los flags están invertidos: `-u` es “sin upload” (solo descarga) y `-d` “sin download” (solo subida) |
| La prueba de velocidad tarda el doble de lo esperado | son dos procesos, uno por dirección; `-M` se aplica a cada fase |
| Un widget de velocidad dice “not permitted” | la app instalada aún no conoce `.speedtest`: rebuild + `./install.sh` antes de copiar el bundle |
| La prueba de velocidad se queda a medias | `.busy` rechaza una segunda prueba; `cancel()` mata el proceso y la primera promesa se rechaza |
| El swipe va al revés | doble inversión de `scrollingDeltaX`: el offset usa el mismo signo que el delta |
| La rueda del ratón no pagina | `phase == .none` siempre es false (OptionSet vs Optional); usa `phase.isEmpty` |
| La rueda salta varias páginas | el ratón emite varios eventos por notch: acumula y aplica `WheelPagingState` |
| Cambias un HTML y no se ve | no subiste `version` en el manifest |
| La ventana de almacenamiento tarda en abrir | el primer escaneo mide las cachés con `du`; capacidad y recomendados salen antes que avanzados |
| Un widget de almacenamiento no puede borrar | correcto: `.storage` solo da `status`/`review`; el borrado es nativo y confirmado |
| Un widget no hereda los tamaños | usa `var(--cornice-*)`; los tokens se inyectan en `:root` antes del HTML |

---

## 16. Añadir un widget

1. Para un ejemplo genérico: `BundledWidgets/<Nombre>.cornicewidget/`. Para uno personal:
   fuera del repo, en una carpeta local de bundles.
2. `id` reverse-DNS único; `apiVersion: 1`; `version` semver.
3. Declara solo las capacidades que uses, con sus listas (`networkHosts`,
   `keychainServices`, `credentials`).
4. Si debe venir activo: `defaultEnabled: true`.
5. Usa `cornice.settings` para opciones y `cornice.language` para textos.
6. No metas el contenido en una tarjeta: el fondo es el panel.
7. Sube la versión si ya existía.
8. Usa los tokens `var(--cornice-*)`; no declares `font-size` propios ni escales por display.
9. `swift test` (el test de bundles lo carga) y captura local con `scripts/screenshot.sh`.
10. **No** lo documentes en `README.md` si es personal (§2). Si es genérico, añade una sección
    y actualiza este archivo si cambia el contrato.

---

## 17. Convenciones

- **Commits**: conventional commits (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`,
  `chore:`), sin nombres, hosts ni datos de widgets personales. Rama `main` mientras no haya
  remoto; si el repo crece, `feature/<nombre>`.
- **Código y UI en inglés**; documentación de trabajo (este archivo) y conversación en español.
- Swift 6 estricto: `@MainActor` en todo lo que toca UI/AppKit; lógica pura separada y
  testeada. Nada de `@unchecked Sendable` salvo justificación.
- No añadir dependencias externas. El bundle se firma ad-hoc con `--options runtime`
  (hardened runtime + library validation).
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
- Aislar los webviews en un servicio XPC sandboxeado (hoy la app no está sandboxeada).
- Más integraciones de infraestructura (servicios self-hosted, CI/PRs, contenedores, red).
