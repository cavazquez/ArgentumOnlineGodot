# Revisión completa de mapas y portales

`tests/world_routes_audit.tscn` carga y renderiza los 290 mapas y los dos extremos
de cada uno de los 852 pares dirigidos de cruce del catálogo del servidor.
Para cada par se centra la cámara sobre una salida representativa y su llegada;
el cálculo del servidor comprueba aparte todas las coordenadas y direcciones.

```sh
python3 tools/smoke-world-routes.py --godot /ruta/al/Godot --output build/world-routes-source
python3 tools/smoke-world-routes.py --client-executable build/r10/pyao-client-r10.x86_64 \
  --output build/world-routes-native
```

La herramienta usa Xvfb y OpenGL real en Linux, conserva el hash del ejecutable
exportado, aísla los directorios del usuario y rechaza errores del motor,
evidencia parcial, máscaras incompletas o caché fuera de presupuesto. El workflow
Linux ejecuta la auditoría sobre el mismo export nativo que prueba con el
servidor instalado. No publica ese export ni crea un Snap.

`rendered-world.json` contiene las máscaras completas observadas en cada mapa y
los pares realmente renderizados. `result.json` resume el resultado, los hashes
y el alcance. `network_crossings: false` es intencional: renderizar los dos
extremos no equivale a enviar WALK por TCP en todas las coordenadas. La prueba
de estrés de caché es adicional y registra los cambios que realmente ejecutó,
en lugar de inferirlos de un número fijo de mapas por ciclo.

El inventario exhaustivo del servidor está en
[`docs/operations/world-routes.md`](https://github.com/cavazquez/pyao-server/blob/main/docs/operations/world-routes.md).
Revisa 59.918 salidas, 239.672 aproximaciones cardinales y la matriz de 84.100
pares ordenados. Los mapas sin salida y los enlaces de un solo sentido se
conservan para revisión; la topología no inventa retornos.

La revisión encontró problemas de llegada, sincronización de bloqueos y
navegación. Están registrados en los issues del servidor
[#348](https://github.com/cavazquez/pyao-server/issues/348),
[#349](https://github.com/cavazquez/pyao-server/issues/349),
[#350](https://github.com/cavazquez/pyao-server/issues/350),
[#351](https://github.com/cavazquez/pyao-server/issues/351),
[#352](https://github.com/cavazquez/pyao-server/issues/352) y
[#353](https://github.com/cavazquez/pyao-server/issues/353).
La clasificación de bordes horizontales del mapa del mundo está registrada en
[#169](https://github.com/cavazquez/ArgentumOnlineGodot/issues/169).
El renderizado puede pasar mientras esos problemas de juego siguen abiertos.
La aceptación por red con dos clientes debe verificar las correcciones antes
de declarar que todos los portales funcionan.
