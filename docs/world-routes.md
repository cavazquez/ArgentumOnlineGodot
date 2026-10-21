# Mapas, portales y topología revisados

El conjunto original tenía 59.918 fuentes de salida. Tras conservar muros y revisar las 131 llegadas sólidas, se sellaron 63 fuentes inválidas y se retargetearon 68 de forma local. El inventario actual contiene 59.855 salidas, 852 pares dirigidos y 239.420 aproximaciones cardinales; el servidor produce además la matriz completa de 84.100 pares ordenados.

La máscara de cada uno de los 290 mapas conserva 10.000 posiciones. Cliente y servidor comparten agua y colisiones sólidas: carteles sólidos, árboles recolectables que bloquean el paso y puertas dinámicas. La puerta abierta 111(97,82) ya no tiene el bloqueo residual del cliente. Las excepciones de portal se envían después de cada carga, antes de habilitar el actor local, conservando el bit de agua.

`tools/build-world-topology.py` reconoce los bordes originales x9→91, x92→10, y7→93 y y94→8, incluidos bordes desplazados y diagonales. No fabrica salidas inversas. La disposición conserva cada mapa en una posición única; el enlace incompatible con una cuadrícula plana se dibuja punteado y naranja, manteniendo sus coordenadas originales. `MapViewCache` precarga los vecinos dirigidos reales dentro de su presupuesto.

Los 275 mapas con acceso y retorno al mundo se declaran jugables. Los otros 15 están señalados como reservados, con acceso administrativo hasta que se diseñen entrada y salida; no se presentan como rutas normales. Las decisiones y la clasificación de los 420 cruces agua/tierra están versionadas en el [servidor](https://github.com/cavazquez/pyao-server/blob/main/docs/world-review.md).

`tools/smoke-world-routes.py` carga y renderiza todos los mapas y los 852 pares con OpenGL real, incluyendo precarga y liberación. Esa cobertura gráfica y estática no equivale a caminar cada salida por TCP.

`tools/audit-terrain.py` compara las 2.900.000 celdas renderizadas contra los fuentes del commit de servidor seleccionado. Distingue agua, sólidos y techos, conserva los hashes de entrada y rechaza cualquier diferencia. El workflow conserva ese contraste junto con el render.

Las puertas tienen una capa dinámica separada de los objetos del suelo: abrir, cerrar o recoger botín no reemplaza la otra capa. El cliente retira el gráfico estático de sus coordenadas registradas y recibe del servidor tanto su aspecto como su colisión antes del actor local. El escenario de dos clientes comprueba las dos mitades de Ullathorpe, el paso abierto, el cierre rechazado sobre un jugador y la persistencia tras reconectar.

El escenario `tools/integration-world.py --scenario world-routes` sí usa dos clientes por TLS y Redis descartable: ida/vuelta, portal interior, mismo mapa, destino ocupado, agua/tierra, barco ausente, habilidad insuficiente, muerte y transición marítima. Cada caso contrasta al actor, al observador y el estado persistido. El ensayo termina en un área segura para separar las transiciones de la observación posterior de sesión y reconexión.

Las pruebas del servidor cubren además reservas simultáneas, cambio del origen durante la transacción, puertas/NPCs/reservas y caída de conexión después del commit. Ninguna de estas pruebas usa un Redis del operador ni publica distribuciones.

La muestra de colisiones elige un cartel y un árbol de las coordenadas revisadas. Los dos clientes se aproximan desde lados opuestos, comprueban su bloqueo y conservan posición en cliente/Redis; se lee el cartel y se obtiene madera del árbol, sin convertir decoración nueva en recurso.
