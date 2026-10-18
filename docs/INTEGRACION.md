# Integración reproducible de la versión 1.0

`tools/integration-world.py` instala un wheel del servidor y su runtime de
`uv.lock` en un venv nuevo. Desde una carpeta temporal inicia Redis 8.10.2
descartable con contraseña, AOF y puerto aleatorio en loopback, el CLI instalado
con TLS y dos procesos Godot de la versión exacta del manifiesto.

El driver `tests/integration_world.tscn` usa las pantallas reales y sus señales:
abre alta desde login, crea dos cuentas efímeras, carga el mapa y sus recursos,
mueve con Input, recibe chat del otro cliente, selecciona y mueve un objeto al
slot 30 esperando el ACK, mantiene ambas sesiones y desconecta. El runner
comprueba las cuentas persistidas y el cierre SIGTERM del servidor. Cada proceso
tiene preferencias XDG separadas; las credenciales se pasan por entorno y nunca
por argumentos o logs.

```sh
# En el servidor, con sus PR de la 1.0 ya incorporados en la rama de prueba:
uv sync --locked --group build
uv build --out-dir /tmp/pyao-candidate
# En este cliente, después de instalar el motor del manifiesto:
GODOT_BIN=/ruta/godot tools/smoke-godot.sh
uv run --project /ruta/pyao-server python tools/integration-world.py \
  --server-project /ruta/pyao-server \
  --wheel /tmp/pyao-candidate/pyao_server-1.0.0rc1-py3-none-any.whl \
  --godot /ruta/godot --output /tmp/pyao-acceptance --seconds 1800
```

La ejecución gráfica requiere X11, por ejemplo un Xvfb exclusivo mediante
`xvfb-run -a -s '-screen 0 1280x800x24' ...`. `--headless` permite un control
rápido. `--seconds 30` sólo verifica el harness; no acredita los 30 minutos de
aceptación. La salida conserva logs, capturas gráficas y `result.json` con ambos
commits, SHA256 del wheel, versiones, duración y resultado. Hay un plazo global
de duración + 240 s; se cierran únicamente los procesos y recursos propios.

Por defecto se usa Docker con la imagen fijada del servidor. Cuando el host no
permite conectividad al bridge, `--redis-runtime /ruta/runtime-extraido` permite
usar el Redis 8.10.2 real extraído de esa imagen, con `redis-server`, `ld-musl`,
`lib/` y `usr-lib/`. Se verifica la versión y se conservan ACL, autenticación,
AOF, aislamiento por directorio y propiedad del proceso. No se acepta un Redis
existente ni se cambian redes o datos del operador.

La prueba usa el cliente desde su checkout para cargar el driver de test. La
validación del Snap instalado y su publicación siguen siendo requisito de #46.

La CI ejecuta un recorrido corto y además instala el Snap estricto construido
sobre el mismo commit. `--snap-installed --snap-audio PulseAudio` abre ese paquete
con un perfil nuevo, CA de prueba y credenciales efímeras. `snap-ui-smoke.py` usa
XTest en un Xvfb exclusivo, comprueba renderizado del mapa, teclado, mouse y un
stream PulseAudio hacia un sink nulo; el runner verifica movimiento e inventario
en Redis. Después se actualiza el Snap local y se compara el hash de las
preferencias. La opción de desarrollo `--ui-executable` permite depurar ese
recorrido sin instalar; su resultado declara `installed=false` y no acredita
confinamiento. La publicación y la instalación desde Store corresponden a #46.
