# Representación del equipamiento

El servidor resuelve cuerpo/ropa, arma o herramienta, escudo y casco desde el
equipo confirmado en Redis. `Anim` identifica las capas accesorias;
`NumRopaje`, el cuerpo de la armadura; `RazaEnanaAnim`, la variante de arma para
personajes pequeños. `GrhIndex` es el icono del objeto y no acredita su apariencia
equipada. Un cambio de orientación con cuerpo cero conserva las capas presentes.

El escenario `--scenario equipment --client-audio PulseAudio` opera por la UI
real en dos clientes. Equipa y reemplaza armadura, ropa, daga, espada, caña, hacha,
piquete, serrucho, bastón, casco y escudo para cada jugador. Exige que dueño y
observador tengan los mismos IDs y recursos SpriteFrames, visibles y con frames
válidos. También recorre cuatro orientaciones, reconexiones, un portal real y el
desequipado. Las capturas `equip-*` muestran ambas ventanas. El escenario está
disponible en la ejecución manual de GitHub Actions sin habilitar paquetes.

La [auditoría completa](equipment-visual-audit.json) comprende 342 piezas y 381
referencias, contando variantes de raza. No acredita cobertura total: faltan el
yelmo 1058 (Anim 2 es casco vacío), el martillo 401 para personajes pequeños
(Anim 77 no existe en el índice original) y la red 543 (sin Anim asignada).
Se siguen en [#180](https://github.com/cavazquez/ArgentumOnlineGodot/issues/180).

Las cinco botas están clasificadas como muebles y carecen de ranura y capa del
avatar. Los anillos del catálogo también carecen de una ranura compatible con el
equipamiento actual; se siguen en
[#367 del servidor](https://github.com/cavazquez/pyao-server/issues/367).
Estas categorías quedan pendientes de implementación.

En el [cliente clásico AO Libre](https://github.com/ao-libre/ao-cliente/blob/master/CODIGO/Areas/TileEngine.bas#L157-L172)
el personaje tiene cuerpo, cabeza, casco, arma y escudo, sin capa independiente de
calzado. Hide Zone conserva esas capas en su cliente Godot.
[The Mana World](https://github.com/themanaworld/tmwa-client-data/tree/master/graphics/sprites/equipment/feet)
sí dispone de sprites separados de botas; su adaptación requiere revisar tamaño,
anclajes, pasos, razas y la licencia de cada recurso que se elija.
La elección y el soporte pendiente se documentan en
[#181](https://github.com/cavazquez/ArgentumOnlineGodot/issues/181).

Para reproducir el inventario de recursos sin ejecutar el juego:

```sh
python tools/equipment_catalog_audit.py --server-project ../pyao-server --output docs/equipment-visual-audit.json
```

La regresión gráfica usa `tools/integration-world.py`, `--source`, `--scenario
equipment`, un directorio `--output` nuevo y el mismo servidor fuente. No exige
exportar binarios ni instalar Snaps. No sustituye una aceptación prolongada.
