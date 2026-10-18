# Habilidades, fabricación y verificación

La ventana Habilidades muestra las 22 habilidades, su nivel, progreso natural y
puntos disponibles confirmados por el servidor. Los botones +/− preparan un
borrador; Aceptar lo guarda. Los avisos de entrenamiento no abren la ventana ni
descartan un borrador. Liderazgo, Navegación, Robustez y Agilidad indican «Manual».

«Usar» selecciona Robar, Supervivencia, Domar o Proyectiles y luego el objetivo
en el mapa; Ocultarse y Meditar actúan sobre el personaje. Talar, Pesca y Minería
usan herramientas y objetivo. El uso de herramientas y la tecla de trabajo
existentes se conservan. Navegación utiliza el barco seleccionado en inventario.

«Fabricar» abre recetas de Carpintería o Herrería; «Fundir» las de Minería. Las
páginas, nombres, materiales y requisitos provienen del servidor. Elegir receta
y cantidad de 1 a 100 y confirmar; la respuesta determina el resultado. Ante
una espera agotada, Reintentar conserva la identidad y evita duplicar consumo.
Los controles requieren la capacidad negociada de acciones de habilidades.

Estadísticas permite consultar los cinco atributos y las habilidades. Los puntos
de nivel corresponden a habilidades; los atributos mantienen tirada, raza, clase
y efectos activos. La ventana admite redimensionado y conserva su botón Cerrar.

Los FX y sonidos de magia se reproducen sobre el objetivo real y en observadores.
Un FX recibido tras desaparecer el NPC derrotado se reproduce transitoriamente
en su última posición y se libera al terminar. La invisibilidad oculta cuerpo y
nombre; su expiración, resurrección y reconexión reciben el estado del servidor.

## Repetir las pruebas

Usar Godot/templates fijados y un checkout del servidor con estas mecánicas.
Desde el servidor, construir primero el wheel y ejecutar con uv:

```bash
uv sync --locked --group build
uv build --wheel --out-dir /tmp/pyao-mechanics-wheel
uv run --locked python ../ArgentumOnlineGodot/tools/integration-world.py \
  --scenario skills --server-project . \
  --wheel /tmp/pyao-mechanics-wheel/pyao_server-1.0.0rc1-py3-none-any.whl \
  --godot /ruta/Godot_v4.7.2-stable_linux.x86_64 \
  --output /tmp/pyao-skills-proof --seconds 30
```

Repetir con `--scenario spells` y otra carpeta de salida. Por defecto se usa un
contenedor Redis descartable. `--redis-runtime /ruta/runtime` admite el runtime
local Redis 8.10.2 descrito por el runner; nunca utiliza la base del operador.
Cada salida debe ser nueva para conservar errores y evidencias de intentos previos.
En un servidor sin escritorio, anteponer `xvfb-run -a -s '-screen 0 800x600x24'`
al comando de uv. Los dos clientes requieren una pantalla gráfica; CI utiliza
ese display virtual y conserva los logs y capturas de ambos procesos.

`skills` crea dos clientes gráficos, asigna las 22 habilidades, ejecuta sus acciones
y comprueba progreso y estado en Redis, ventanas, navegación, reconexión y reinicio
del servidor con mascota permanente. `spells` ejecuta los 45 hechizos, rechaza los
diez reservados y exige FX con cuadros visibles y reproducción real de WAV en los
dos clientes para los hechizos configurados. También compara HP, hambre,
modificadores temporales, apariencia y mascotas; confirmar un cast sin aplicar
su efecto no acredita el caso. Los FX deben pertenecer al actor correcto.
Las cuentas, posiciones y recursos
controlados pertenecen exclusivamente al fixture. Las acciones pasan por la UI,
paquetes, TLS y servicios reales; no se publica ni modifica una partida del usuario.

`tools/smoke-godot.sh` incluye protocolo, asignación, fabricación, estadísticas y
limpieza de FX letales. `python3 -m unittest discover -s tools/tests` comprueba el
clasificador de exportación y la evidencia de aceptación. Exportar con
`GODOT_BIN=/ruta/godot tools/export-linux.sh`.

Estos ensayos son regresiones de desarrollo. El escenario `r10` predeterminado
mantiene su puerta de aprobación prolongada de 30 minutos, export nativo, commits
limpios y pruebas de distribución. Una regresión corta no reemplaza esa aceptación
ni publica automáticamente otra revisión del Snap.
