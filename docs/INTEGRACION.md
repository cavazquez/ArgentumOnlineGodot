# Integración reproducible de la versión 1.0

`tools/integration-world.py` instala un wheel del servidor y el runtime de
`uv.lock` en un venv nuevo, fuera de los checkouts. Compara todos los archivos
instalables del wheel con la fuente declarada. Inicia Redis 8.10.2 descartable,
autenticado, con AOF y puerto aleatorio en loopback; el CLI instalado con TLS y
dos clientes Godot de la versión exacta del manifiesto.

## Recorrido y evidencia

`tests/integration_world.tscn` y `tests/r10_client.gd` operan las pantallas,
formularios, señales, botones e Input reales. `tools/r10_world.py` coordina los
procesos mediante archivos privados y contrasta los resultados con Redis. No
reemplaza las acciones de los jugadores con llamadas a servicios Python.

El recorrido verifica:

- Alta de doce clases, cinco razas, ambos géneros y las seis ciudades propias.
- Uso en slots 1, 25, 26 y 30; equipar/desequipar, intercambio de slots ocupados,
  tirar/recoger el mismo objeto, banco, comprar/vender y trade confirmado/cancelado.
- Chat público, grito y privado con acentos; crear/invitar/aceptar/chat/salir de
  party y clan, incluyendo la ventana de detalles del clan. La experiencia de
  ambos miembros se contrasta con el reparto persistido, sin recompensa duplicada.
- Curación y daño con objetivos, cancelación y objetivo inválido sin cobro;
  meditación, aprendizaje de pergamino sin consumo duplicado y asignación de skills.
- Combate real contra un NPC y experiencia, muerte por NPC, resurrección por
  hechizo y sacerdote con restauración de apariencia y una nueva vida.
- Invocar, observar seguimiento y liberar mascotas; talar, minar y pescar con los
  recursos y herramientas propios; atravesar una salida de mapa original.
- Reordenar hechizos y conservar el libro, cada ítem, cantidad y equipamiento al
  reconectar. En el ensayo largo, hambre y sed deben disminuir en la UI.
- Dos sesiones con movimiento y chat durante al menos 1800 segundos medidos por
  cada Godot, más el recorrido anterior; cierre SIGTERM con dos sesiones TLS activas.

`r10-scenarios.json` acredita cada escenario y `r10-actions.json` los recibos de
Godot y observaciones. Se conservan logs, capturas, `r10-fixture.json`,
`wheel-source.json` y `result.json` con ambos commits, versión común, SHA256 del
wheel/export/configuración, herramientas y duración medida. La procedencia del
export debe coincidir en commit y hashes; el ensayo largo exige que se compilara
desde una fuente limpia. La aprobación final
adjunta además los resultados R01 a R09 de ese mismo par; el campo
`r10_gameplay_passed` sólo acredita este recorrido de juego.

Los `.import` versionados incluyen los defaults del Godot fijado. CI exige que
importar y ejecutar los smokes conserve limpio el checkout. La normalización
sólo explicita opciones del importador; conserva los bytes de los recursos propios.

## Repetir el ensayo

```sh
# Servidor, después de incorporar las correcciones del candidato:
uv sync --locked --group build
uv build --out-dir /tmp/pyao-candidate
# Cliente, con motor y templates del manifiesto instalados:
GODOT_BIN=/ruta/godot tools/smoke-godot.sh
GODOT_BIN=/ruta/godot tools/export-linux.sh --r10
# Ambos checkouts deben estar limpios y sus commits fijados:
xvfb-run -a -s '-screen 0 1280x800x24' \
  uv run --project /ruta/pyao-server python tools/integration-world.py \
  --server-project /ruta/pyao-server \
  --wheel /tmp/pyao-candidate/pyao_server-1.0.0rc1-py3-none-any.whl \
  --godot /ruta/godot \
  --client-executable build/r10/pyao-client-r10.x86_64 \
  --output /tmp/pyao-acceptance --seconds 1800
```

El preset `Linux R10 Acceptance` incluye los drivers y se identifica con la
feature `r10_acceptance`. Su `override.cfg` versionado selecciona la escena y
activa el flush de logs del template release. Debe quedar junto al ejecutable en
`build/r10/`. El preset de producción y el Snap excluyen los tests y conservan
su escena principal. El export de aceptación no se publica como cliente.

`--seconds 10` y el modo editor sirven para desarrollar el harness.
`--headless` permite depuración sin pantalla. Ninguno acredita una aceptación
larga: 1800 segundos exige dos exports nativos gráficos y checkouts limpios.
Hay plazos por acción y 600 segundos para los escenarios; el worker completo
vence en duración + 900 segundos. Se cierran sólo los procesos propios.

## Datos y aislamiento

`tests/r10_fixture.toml` declara únicamente personajes efímeros, recursos y
hechizos del catálogo versionado. Se preparan posición, stats y pertenencias
sólo con las sesiones desconectadas. La instancia usa cuotas de autenticación
120 por IP y 40 por cuenta para permitir altas/reconexiones del ensayo. Desactiva
únicamente el impuesto periódico al oro para las aserciones de conservación;
sus reglas se verifican en la suite del servidor. Se copian los catálogos y mapas
del wheel sin sustituirlos; sólo se acotan los spawns de NPC del sandbox.

Cada Godot tiene preferencias XDG separadas. Las credenciales canarias efímeras
se pasan por entorno, nunca por argumentos, y se comprueba que no aparezcan en
los logs. No se acepta un endpoint Redis externo ni se usan cuentas reales.

Por defecto Redis usa la imagen Docker fijada del servidor. Si el host no permite
conectividad al bridge, `--redis-runtime /ruta/runtime-extraido` usa el Redis
8.10.2 real extraído de esa imagen (`redis-server`, `ld-musl`, `lib/`, `usr-lib/`).
Se verifican versión, ACL, autenticación, AOF y propiedad del directorio/proceso.
No se modifican redes ni datos del operador.

## Paquete instalado y R01 a R09

CI compila los dos presets, ejecuta los escenarios cortos y construye e instala
el Snap estricto del mismo commit. `--snap-installed --snap-audio PulseAudio`
abre el paquete con un perfil nuevo, CA de prueba y credenciales efímeras.
`snap-ui-smoke.py` usa teclado/mouse XTest en Xvfb, espera mapa, minimapa, consola
e inventario, verifica movimiento y drag contra Redis y un stream PulseAudio en
un sink nulo. Luego actualiza el paquete y compara el hash de preferencias.
`--ui-executable` permite depurar ese flujo sin Snap y declara `installed=false`.

Si el commit publicado en `latest/edge` coincide, CI instala desde la Store; de
lo contrario usa el artefacto local y registra `snap_install_source=artifact`.
La instalación desde la Store se repite después de publicar el commit integrado.
El artefacto `godot-world-integration-N` identifica cada intento de CI. Reejecutar
sólo `integration-world` permite verificar la instalación desde la Store con los
exports y el Snap ya validados del mismo run, conservando la evidencia anterior.

Para R01 a R09 se adjuntan también, en el mismo servidor candidato: suite completa,
lint/tipos, dataset, distribución instalada, fixtures y framing del contrato,
pruebas TLS/privacidad/UI de Godot, y operaciones Redis reales de autenticación,
contraseña, comercio/banco/suelo, cadencia/magia/muerte, persistencia, backup,
restauración y migraciones. Los scripts de protocolo complementan los dos
clientes nativos; no sustituyen el recorrido gráfico de R10.
