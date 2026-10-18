# Motor y templates fijados

El cliente usa **Godot 4.7.2 stable Standard**, build oficial `ed1daf0bf`, con **export templates 4.7.2.stable**. La versión utilizable por herramientas está en [`.godot-version`](../.godot-version); [tools/godot-release.json](../tools/godot-release.json) contiene las URLs oficiales y SHA256 de motor Linux amd64 y templates verificados.

Se eligió la última versión estable publicada al 18/10/2026 de una rama con soporte activo. La 4.8 disponible en esa fecha es beta. Fuentes oficiales: [archivo de 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/) y [política de soporte](https://docs.godotengine.org/en/stable/about/release_policy.html). Una actualización posterior debe cambiar la versión fijada y repetir las comprobaciones; no se recomienda un rango `4.x+` abierto.

## Preparar el motor

Descargar los ZIP/TPZ desde las URLs del manifiesto y comprobar sus SHA256 antes de extraerlos. Usar Standard, ya que este proyecto no requiere .NET. El TPZ es un ZIP: extraer su directorio `templates/` y copiar su contenido a `~/.local/share/godot/export_templates/4.7.2.stable/` en Linux, o instalarlo desde el administrador de templates del editor.

Desde la raíz del cliente:

```bash
export GODOT_BIN=/ruta/Godot_v4.7.2-stable_linux.x86_64
./tools/check-godot.sh
./tools/check-godot.sh --templates
"$GODOT_BIN" --editor --path .
```

`check-godot.sh` falla ante otro motor. Con `--templates` verifica `version.txt` y ambos templates Linux. Para validar una instalación en otra ruta puede usarse `GODOT_TEMPLATES_DIR`; eso sólo cambia la comprobación, mientras que Godot sigue buscando sus templates en su ruta estándar de datos.

## Comprobar la migración

```bash
GODOT_BIN=/ruta/Godot_v4.7.2-stable_linux.x86_64 ./tools/smoke-godot.sh
```

El script importa el proyecto y ejecuta `tests/engine_smoke.tscn` con datos de usuario temporales. Además del código de salida, rechaza los errores que Godot imprime incluso cuando termina con cero. Comprueba el formulario de login, carga y atributos de creación, clases/razas/ciudades propias, mapas 1 y 34, renderizado/actualización de 30 slots de inventario, ventana de clanes y shaders. El recorrido tiene un límite interno de 20 segundos. Se puede repetir con renderizado OpenGL en Linux:

```bash
xvfb-run -a "$GODOT_BIN" --path . --rendering-method gl_compatibility res://tests/engine_smoke.tscn
```

Estas pruebas verifican la migración del motor y sus recursos. El recorrido de red contra servidor y Redis pertenece al [issue #60](https://github.com/cavazquez/ArgentumOnlineGodot/issues/60), después de las correcciones de protocolo y de integración. Las pruebas no declaran resueltas las diferencias actuales del selector de ciudades ni la capacidad configurada del inventario: esos cambios siguen el alcance de la 1.0.

## Exportar Linux amd64

```bash
./tools/check-godot.sh --templates
mkdir -p build
"$GODOT_BIN" --path . --rendering-method gl_compatibility --export-release "Linux Desktop" build/pyao-client.x86_64
./build/pyao-client.x86_64
```

La exportación se validó con OpenGL. En un entorno sin pantalla, usar Xvfb:

```bash
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a "$GODOT_BIN" --path . --rendering-method gl_compatibility --export-release "Linux Desktop" build/pyao-client.x86_64
```

Al exportar este proyecto desde una copia limpia con `--headless`, el renderizador dummy produjo errores `Image width specified (0 pixels)` después de empaquetar. La ruta anterior con OpenGL evita esos errores y es la que debe reproducir la CI de #11. La importación y el recorrido de escenas sí pasan en headless.

El preset incluye mapas, gráficos, sonidos, recursos y los índices binarios/INI leídos mediante `FileAccess`; el PCK queda embebido. No requiere paquetes externos `index.pck`, `graphics.pck`, `sounds.pck` ni `maps.pck`: el arranque puede informar que no están presentes y cargar los recursos propios incorporados. Los directorios `Tools/`, `tools/` y `tests/` se excluyen del producto. Se corrigió también el filtro del preset Windows existente; su ejecución nativa no forma parte de esta validación Linux.

La CI `Cliente Linux` importa desde checkout limpio, ejecuta escenas y privacidad y exporta con OpenGL software bajo Xvfb. Descarga motor/templates del manifiesto y verifica SHA256; conserva logs y el ejecutable durante siete días. No utiliza caché UID ni un perfil `user://` del operador. Puede reproducirse con `tools/install-godot.py --destination /ruta/temporal` y `tools/export-linux.sh`. Construir/publicar Snap `pyao-client` continúa en [#46](https://github.com/cavazquez/ArgentumOnlineGodot/issues/46).

## Cambios necesarios al migrar

- `project.godot` declara 4.7 y conserva GL Compatibility, inputs y autoloads propios. No se incorporaron herramientas privadas de editor ni se importó el dataset de Hide Zone.
- La creación apuntaba a `res://maps/Map1.tscn`; se corrigió la mayúscula del directorio `Maps/`, necesaria en Linux.
- La ventana de fundación de clanes tenía un nodo `VBox` sin `parent="."`. La exportación ahora puede instanciar esa escena.
- Se repararon los contenedores RIFF de `Assets/Sfx/34.wav`, `65.wav`, `83.wav`, `142.wav`, `151.wav`, `152.wav` y `154.wav`: tamaños/padding y metadatos dañados provocaban errores de importación. Sus bytes PCM, formato y frecuencia permanecen idénticos; En 34/142/151 sólo se conservaron los chunks de formato y audio; en 65/83/152/154 se añadió el byte de padding final faltante y se actualizó el tamaño RIFF.
- El editor añadió opciones por defecto a 2773 `.import`: compresión UASTC/RDO en cero, canales RGBA de identidad y modulación de glifos desactivada. Se revisaron y se omitieron esas adiciones redundantes para conservar la configuración original de cada recurso. Una importación local puede volver a agregarlas; no son cambios visuales necesarios para la migración.

Validación del 18/10/2026: importación sin errores, recorrido de escenas en headless y OpenGL (Mesa/llvmpipe), exportación Linux con OpenGL y los templates fijados y arranque del binario con recursos embebidos. Los avisos de V-Sync/entrada X11 bajo Xvfb describen el entorno de prueba.
