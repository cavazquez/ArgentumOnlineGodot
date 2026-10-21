# Propiedad de recursos gráficos

Las vistas inactivas permanecen dentro de `MapViewCache`; cada expulsión termina su propiedad y la precarga se cancela al salir. `GameScreen.Retire` desconecta las suscripciones globales, descarta paquetes pendientes y retira el cursor propio antes de liberar la pantalla.

Los objetos altos y las puertas dinámicas usan un ancla `Node2D` para participar en el orden por profundidad. Su `Sprite2D` pertenece al ancla sin ordenamiento de hijos, como las capas de un personaje. La recogida, sustitución o cambio de mapa libera ese propietario completo. La identidad de una puerta está separada de la del botín que pueda caer sobre su casilla.

Una reproducción acotada con Godot 4.7.2 y OpenGL real distinguió las rutas: los ciclos de mapas sin objetos y con botín pequeño terminaban limpios; reemplazar sprites dinámicos directamente en la capa ordenada dejaba recursos al salir. La jerarquía con anclas elimina esa fuga en la misma reproducción conservando la posición usada para ordenar. Esto documenta la ruta observada y su corrección; no atribuye una causa interna al motor.

`tests/door_layers.tscn` repite doce ciclos con puertas abiertas/cerradas, botín en su misma casilla, objetos altos y cambios de mapa. Verifica las referencias débiles de los gráficos retirados. El CI ejecuta la escena con renderizado real y rechaza errores y avisos de fugas. El escenario integral `npc-loot` mantiene además las 29 categorías, recogida, equipo/consumo, reconexión y el diagnóstico final del destructor: imprimir PASS antes de ese cierre no basta para aprobar.
