# PyAO Client en Snap

El paquete se llama `pyao-client`, usa confinamiento `strict`, base `core24` y
arquitectura Linux amd64. Esta primera entrega apunta a `latest/edge`. El perfil
gráfico es OpenGL por X11; en escritorios Wayland se usa XWayland. La validación
de Wayland nativo corresponde a otra entrega.

El motor y los templates son exactamente los de `tools/godot-release.json` y se
verifican por SHA256. `snap/toolchain.json` fija Snapcraft 9.1.4, revisión 19274.
La [extensión GPU oficial](https://ubuntu.com/docs/snapcraft/9/reference/extensions/gpu-extension/)
provee las bibliotecas gráficas para core24. El paquete usa red, X11, gráficos,
audio y escritorio. El lanzador guarda configuración, datos y caché bajo
`$SNAP_USER_COMMON`, que se conserva al actualizar.

## Construcción

Con Docker/LXD y Snapcraft disponibles, desde un checkout limpio:

```bash
python3 tools/build-snap.py
```

El comando exige la herramienta fijada, registra el commit y ejecuta Snapcraft en
LXD. El propio build descarga el motor/templates verificados, importa, corre los
smokes y exporta Linux. Incluye el PCK embebido con Maps, Assets, Resources y los
datos cargados dinámicamente; los tests y herramientas no entran en el paquete.
`--allow-dirty` sirve para un artefacto local de revisión y registra `dirty=true`;
no se usa para publicar. La procedencia y licencias quedan también dentro del
Snap en `share/doc/pyao-client/`.

La CI existente ejecuta primero importación/exportación y luego el mismo comando
de Snap en un runner descartable. Conserva paquete, SHA256, log y procedencia.
Si el proveedor LXD local no tiene red, el build puede ejecutarse en CI sin cambiar
las reglas de red del equipo de trabajo.

## Instalación y prueba local

```bash
sudo snap install ./pyao-client_VERSION_amd64.snap --dangerous
pyao-client
snap connections pyao-client
```

Comprobar menú, renderizado, entrada, audio y cierre; crear una cuenta sintética,
entrar a un servidor PyAO compatible, cargar mapa y probar chat/inventario. La
prueba del paquete instalado debe hacerse sin depender del checkout ni del editor
Godot del host. Con una CA de prueba privada, copiar el certificado público al
directorio común del Snap y seleccionarlo desde las preferencias del cliente.
Las claves no se guardan en preferencias.

## Entrega coordinada de servidor y cliente

Las dos aplicaciones conservan la misma versión `1.0.0rc1`. La CI construye
artefactos y nunca los publica automáticamente. El mantenedor prepara un único
manifiesto JSON con estos campos:

- `version`: `1.0.0rc1`; `channel`: `latest/edge`.
- `sources`: claves `pyao` y `pyao-client`, cada una con `repository`, `commit`
  completo fusionado en main y `ci_runs` (IDs de ejecuciones exitosas de ese commit).
  Se exigen `CI` y `Server Snap` del servidor y `Cliente Linux` del cliente.
- `packages`: exactamente servidor amd64/arm64 y cliente amd64. Cada entrada
  contiene `name`, `architecture`, `file` y `sha256`. Se comprueban metadata,
  confinamiento estricto, versión y procedencia limpia dentro de cada Snap.
- `evidence`: referencias `r10`, `upgrade` y `requirements`, cada una con `file`
  y `sha256`. Las rutas se resuelven respecto del archivo que las contiene.

`r10` es el `result.json` de `tools/integration-world.py`: dos exportaciones
nativas gráficas durante al menos 1800 segundos cada una, todos los escenarios
funcionales, servidor instalado desde wheel verificado y cierre de ambas sesiones
TLS. Debe identificar exactamente los dos commits candidatos. `upgrade` contiene
el resultado real de `src.operations.redis_schema selftest`, más `server_commit`:
backup/restauración, migración idempotente, reinicio, recuperación y configuración
heredada, sin datos de producción. `requirements` identifica `server_commit` y
`client_commit`, y `requirements.R01` a `R09`, cada uno con `passed: true` y una
lista `evidence` de referencias `{file, sha256}` a pruebas verificables.

Desde la cuenta local de Snapcraft ya autenticada, con `gh`, `curl` y
`unsquashfs` disponibles:

```bash
python3 tools/release-pair.py check /ruta/par-rc1.json
python3 tools/release-pair.py prepare /ruta/par-rc1.json --output /ruta/preparacion-nueva
# Sólo cuando los tres uploads terminaron y el recibo indica ready:
python3 tools/release-pair.py promote /ruta/preparacion-nueva/state.json
snapcraft status pyao-client
snapcraft status pyao
```

`prepare` copia los candidatos, guarda hashes y canales anteriores y carga todos
los paquetes **sin `--release`**. No cambia canales. Un rechazo o resultado incierto
del upload bloquea la promoción; revisar el log y las revisiones de la cuenta antes
de repetir, para no duplicar una carga cuyo resultado se perdió.

`promote` vuelve a comprobar fuentes, CI, evidencias, bytes y canales. Sólo entonces
promueve las tres revisiones consecutivamente desde el mismo proceso. La Store
opera cada nombre/revisión por separado: el recibo registra inicio y final del
intervalo real, sin prometer simultaneidad atómica. Si falla incluso una respuesta
después de cambiar un canal, repone **todas** las revisiones anteriores y verifica
sus hashes públicos. Si el proceso se interrumpió durante la promoción:

```bash
python3 tools/release-pair.py recover /ruta/preparacion-nueva/state.json
```

Conservar `state.json` y los logs privados. Una recuperación no confirmada queda
como `rollback-failed` y requiere revisar ese recibo antes de otra publicación.
El publicador serializa procesos del mismo usuario en la máquina; coordinar con
los demás mantenedores para que no publiquen desde otro equipo durante la entrega.
Las credenciales permanecen en Snapcraft y nunca entran en manifiestos ni paquetes.

Después, descargar las revisiones de Store y comparar SHA256/procedencia con los
candidatos. Ejecutar `Login entre Snaps publicados` mediante `workflow_dispatch`,
indicando las dos revisiones amd64, commits y SHA256 del recibo de esa entrega.
Esta prueba instala ambos paquetes firmados en un runner descartable y comprueba
alta, login, movimiento, inventario, reinicio y persistencia. Adjuntar su resultado
al recibo de publicación antes de dar la entrega por terminada.

Actualizar y volver a una revisión anterior:

```bash
sudo snap refresh pyao-client --edge
sudo snap revert pyao-client
```

La construcción de la receta no acredita una publicación en Store ni una prueba
completa del paquete instalado. Esas evidencias se registran por separado en #46
y en el recorrido conjunto #60.

La versión pública de cliente debe coincidir exactamente con la del servidor: el candidato actual es `1.0.0rc1`. El commit no se agrega al número de versión; queda en `share/doc/pyao-client/provenance.json` y `source-commit`.
