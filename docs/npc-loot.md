# Recorrido de botín con dos clientes

```sh
uv run --project ../pyao-server python tools/integration-world.py \
  --source --scenario npc-loot --server-project ../pyao-server \
  --godot /ruta/al/Godot_v4.7.2-stable_linux.x86_64 \
  --output /tmp/pyao-npc-loot --seconds 30
```

El ensayo crea su propio servidor y Redis autenticado, dos personajes y dos
Godot gráficos. No acepta una partida existente. Recorre las 29 categorías de
objetos normales: armas, armaduras, accesorios, consumibles, herramientas,
materiales, embarcaciones y otros transportables. Para cada categoría mata un
NPC por el protocolo, observa el mismo sprite en ambos clientes, recoge el oro y
el objeto y contrasta inventario, nombre, tipo y stats con Redis y el catálogo.
Los casos incluyen golpe físico, veneno y hechizo directo.

Armas, armaduras, escudos y cascos se equipan y desequipan; los indicadores deben
mostrar los límites reales y volver a cero. Los alimentos y bebidas recogidos
se consumen por la interfaz. Se guardan capturas de ambos clientes, recibos de
acciones y los resultados por categoría.

La copia descartable de la política fuerza oro y un resultado de cada categoría.
Conserva los pools, stats, límites de cantidad y selección de calidad reales.
Esto acredita el recorrido de red/UI; las probabilidades normales y el sorteo de
cada ID elegible se comprueban en el servidor. El informe identifica explícitamente
este ajuste y no lo presenta como una distribución natural ni como una nueva
aceptación prolongada de toda la versión 1.0.

`Cliente Linux` ofrece `test_gameplay=npc-loot`: construye el wheel del servidor,
exporta el cliente y ejecuta este mismo recorrido con los productos instalados.
La prueba no publica en Snap Store ni en GitHub Releases. `test_gameplay=all`
también incorpora el escenario.
