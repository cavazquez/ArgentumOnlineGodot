# Jugabilidad de la RC2

El cliente conserva el protocolo, datos y reglas propios de PyAO. Daño flotante,
proyectiles y flechas aparecen sólo cuando el servidor negocia las capacidades
16 y 32. Los eventos 246 y 247 incluyen identidad, mapa y extremos; sus fixtures
están compartidas con el servidor. Los efectos nunca modifican vida, daño ni maná.
Opciones permite desactivar o reducir estas animaciones.

El HUD soporta una ventana mínima de 800×600 y ventanas panorámicas. La zona del
mundo crece; los paneles conservan sus tamaños e índices. Aumentar la ventana no
amplía las entidades ni el alcance autorizado por el servidor. El fondo usa nueve
regiones y los puntos de interacción se transforman desde el viewport.

Controles permite reasignar teclado y gamepad, detectar conflictos y restaurar el
preset. La captura de una tecla bloquea acciones del mundo; Escape la cancela.
Preferencias de audio, texto, cursor, nombres y efectos se guardan atómicamente en
`user://options.cfg`, conservando claves anteriores. Los controles usan
`user://controls.cfg`. Estos archivos contienen preferencias de la máquina;
el estado persistente de la partida sigue en Redis.

El clic derecho del minimapa abre el mapa mundial. No teletransporta. Sus enlaces
se generan desde los datos reales del servidor:

```sh
python3 tools/build-world-topology.py --source ../pyao-server/map_data \
  --metadata ../pyao-server/data/world/map_metadata.toml
```

El catálogo incluye conexiones dirigidas, geográficas y teleports, mapas aislados
y contradicciones de disposición en `layout_conflicts`. Las contradicciones no
reescriben mapas ni inventan reciprocidad. La caché carga una escena por frame,
conserva como máximo tres vistas vecinas y limita su estimación de nodos/celdas a
64 MiB. Las texturas compartidas del motor quedan fuera de esa estimación. Al
promover una vista se retiran entidades anteriores y se conserva el estado
confirmado de puertas y objetos del mapa activo.

La precarga se difiere al hilo principal: mapas vecinos y activos comparten
Tilesets y texturas. Evitar cargas concurrentes de esos recursos elimina los
bloqueos y RIDs gráficos sin inicializar observados al reconectar. La regresión
gráfica usa el export nativo con OpenGL real, recorre mapas y destruye sus
viewports en 80 ciclos; falla ante cualquier error de Godot:

```sh
python3 tools/smoke-map-cache.py --client-executable build/r10/pyao-client-r10.x86_64 \
  --output build/map-cache-stress --cycles 80
```

Las máscaras de agua también proceden del servidor. `tools/build-water-masks.py
--source ../pyao-server/map_data` actualiza únicamente ese bit de las escenas y
genera `protocol/water-masks.json`. `--check` verifica las 290 escenas sin escribir.
El cargador, exportador y caché usan la misma máscara. Esto corrige costas cuyo
gráfico superior ocultaba agua al clasificador anterior del cliente; gráficos,
techos y bloqueos originales se conservan. Navegar sobre agua respeta la
validación de embarcación y ocupación del servidor.

Las 112 pistas de `Assets/Music` se renderizan desde los MIDI originales del
cliente AO incluido en pyao-server. `manifest.json` registra los hashes de fuentes,
resultados y SoundFont. La conversión usa FluidSynth 2.4.8, FluidR3_GM y FFmpeg:

```sh
OMP_NUM_THREADS=1 OMP_THREAD_LIMIT=1 python3 tools/bake-music.py \
  --source ../pyao-server/clientes/ArgentumOnline0.13.3-Cliente-Servidor/client/MIDI \
  --soundfont /usr/share/sounds/sf2/FluidR3_GM.sf2
```

Se conserva la composición original y se distribuye Ogg mono de 22050 Hz.
PLAY_MIDI contiene un único byte de pista; las pistas de mapa se repiten hasta
ser reemplazadas. Una pista inexistente tiene diagnóstico y deja silencio.
La música tiene volumen independiente, sin modificar los identificadores SFX.

`tools/export-linux.sh` genera `build-info.json` con el commit. La vista de Opciones
muestra versión, motor, plataforma y renderer y permite copiar un diagnóstico
acotado; no incluye credenciales, rutas privadas ni payloads.

La campaña ampliada se ejecuta con `tools/integration-world.py --scenario full`.
Incluye R10, las 22 habilidades, catálogo de hechizos en ambos sentidos, robo de
objetos, barcos, pesca por distancia, maná, interfaz y carga. Sólo prepara fixtures
con las cuentas desconectadas; las actividades se ejecutan por los clientes. Una
ejecución corta no reemplaza la aceptación de 1800 segundos por cliente.
