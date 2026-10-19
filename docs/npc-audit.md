# Muestra breve de NPC y control de audio

El escenario `npcs` de `tools/integration-world.py` usa el catálogo completo del
servidor sin reescribir `map_npcs.toml`; verifica su SHA256 al terminar. Crea dos
cuentas efímeras y opera sus pantallas por Godot/TLS. Sólo prepara posición y
salud de las cuentas de prueba mientras están desconectadas.

```bash
xvfb-run -a ../pyao-server/.venv/bin/python tools/integration-world.py \
  --server-project ../pyao-server --source \
  --godot /ruta/al/editor_fijado --output /tmp/npc-clients \
  --seconds 10 --scenario npcs
```

Requiere el entorno existente del servidor, Docker y el editor fijado en
`tools/godot-release.json`. No instala dependencias ni genera exports en modo
fuente. El resultado acredita identidad, posición y apariencia autoritativas,
reconexión, interacción comercial, transición sin NPC del mapa anterior y una
criatura hostil visible en dos clientes. Guarda las capturas `npc-world`,
`npc-hostile`, `npc-map-change` y `npc-reconnected`.

La posición se compara dentro del rango de actualización del servidor. Los
actores fuera de rango conservan la última posición recibida; su identidad y
apariencia siguen comprobándose. También se rechaza un actor que aparece cerca
del jugador aunque su posición autoritativa ya esté lejos. Los archivos
`npc-difference-1.json` y `npc-difference-2.json` conservan las diferencias.

La revisión detectó y corrigió [cliente #137](https://github.com/cavazquez/ArgentumOnlineGodot/issues/137):
el handler convertía una posición absoluta repetida en un paso al sur y no
sincronizaba saltos de varios tiles. La regresión comprueba reposo, duplicado
durante una animación, movimiento adyacente y corrección sin interpolación vieja.
Se verificó que falla con el código anterior y pasa con el handler corregido.

`mechanics_smoke.gd` comprueba adicionalmente bytes PlayWave, sus coordenadas y
la reproducción de WAV reales 47/103/62 por el handler del juego. Son controles
positivos del parser/reproductor. **No acreditan las voces ausentes del catálogo
de NPC del servidor**, ni sustituyen una prueba del evento real de combate.

El 19 de octubre de 2026 esta muestra pasó con dos Godot 4.7.2 desde fuentes y
Redis 8.10.2 propio. La campaña prolongada R10 quedó expresamente fuera del
alcance. Los problemas de voces están registrados en
[servidor #311](https://github.com/cavazquez/pyao-server/issues/311) y
[#316](https://github.com/cavazquez/pyao-server/issues/316); el recurso histórico
174 ausente se sigue en [cliente #136](https://github.com/cavazquez/ArgentumOnlineGodot/issues/136).

La evidencia por los 290 mapas, el reinicio y los cupos se mantiene en la
[auditoría del servidor](https://github.com/cavazquez/pyao-server/issues/307).
