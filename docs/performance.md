# Índices de entidades y perfil del juego

Implementación del issue #164, compatible con el protocolo del servidor
`1.0.0rc3`. `MapContainer` localiza personajes por ID/celda y objetos por celda
mediante diccionarios. Las bajas usan intercambio con el último slot del array.
Los setters de `Character` mantienen la posición lógica separada de la
interpolación gráfica. Si hay actores superpuestos se conserva el primero creado.
Las actualizaciones de una celda dependen de su ocupación local; las búsquedas por
ID y objeto tienen costo medio O(1). El almacenamiento adicional es O(entidades).

Se limpian referencias al liberar nodos, cambiar de mapa, reemplazar objetos y
reutilizar IDs antes del borrado diferido. `GameWorld` asigna identidad y celda
antes de registrar el actor. Las regresiones están en `tests/entity_indexes.gd`
y se ejecutan dentro de `tools/smoke-godot.sh`.

En la fixture de 5.000 nodos sintéticos, buscar el último ID pasó de 122,96 a
0,15 µs p50; por posición de 143,87 a 0,25 µs. Mover a otra celda y volver cuesta
1,58 µs; retirar y registrar nuevamente, 3,46 µs. El monitor de memoria de esa
fixture sube de 18,35 a 35,34 MB, incluyendo diccionarios de referencia. No mide
renderizar 5.000 personajes ni la capacidad de 5.000 conexiones.

Ejecutar `tests/structure_benchmark.tscn` con Godot 4.7.2 y
`PYAO_STRUCTURE_OUTPUT=/ruta/resultado.json`. Headless mide índices y memoria;
la ejecución gráfica agrega carga/caché de mapas. Los percentiles se conservan
como evidencia, sin umbrales inestables de tiempo en CI.

`tools/integration-world.py --source --scenario structure-profile` ejecuta dos
clientes gráficos, servidor TLS y Redis propios. Compara jugadores concentrados
con/sin lector lento y distribuidos en dos mapas. `--server-profile` permite
activar el diagnóstico acotado del servidor fuente; requiere que su checkout
incluya `tools/profile_runtime.py`. El benchmark del servidor mide ingreso
completo con un PONG ordenado después de LOGIN y registra las primeras
estadísticas aparte. Así no clasifica el resto del spawn como RTT de juego.

La prueba local pasó login, reconexión, inventario/libro, combate, muerte/revivir,
navegación de ambos clientes y cruce de salida marina. Son regresiones sobre
fuentes con renderizado real, independientes de una aceptación prolongada o de
una publicación de paquetes. Los resultados completos, complejidades y hashes se
conservan en [la documentación del servidor](https://github.com/cavazquez/pyao-server/blob/main/docs/operations/runtime-performance.md).
