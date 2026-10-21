# Integración de escritorio

El icono propio está en `Assets/Branding`, con SVG editable, PNG de varios tamaños, ICO, ICNS, licencia y manifiesto SHA256. El icono del proyecto y las exportaciones Windows/macOS usan esos recursos. Se regenera con `tools/build_icons.py`.

La bandeja ofrece «Mostrar cliente» y «Salir del cliente», con el estado de conexión en el título. En Opciones, «Al cerrar o minimizar, mantener en bandeja» se guarda por perfil y está desactivada inicialmente. Minimizar no pausa el juego y conserva también la entrada de la barra de tareas/dock. Sin host de bandeja la ventana sigue siendo accesible.

Windows/macOS usan [StatusIndicator](https://docs.godotengine.org/en/4.7/classes/class_statusindicator.html) del motor fijado. Linux usa el puente C GTK3/Ayatana en `desktop/tray_linux.c`: `python3 tools/build_tray.py` lo genera en `build/desktop/pyao-tray`. Para compilar se requieren `gcc`, `pkg-config`, `libgtk-3-dev` y `libayatana-appindicator3-dev`; no se añade Python al cliente distribuido. Los paquetes Linux lo llevan junto al ejecutable; Snap agrega las bibliotecas de ejecución y el plug `unity7`. Al cerrar, la preferencia de bandeja sólo minimiza si se confirmó un host real. Godot no permite ocultar su ventana principal: se conserva la entrada habitual de barra/dock y se puede restaurar desde el indicador.

El servidor tiene un indicador independiente y una parada gradual; ver [su documentación](https://github.com/cavazquez/pyao-server/blob/main/docs/desktop.md). Cerrar ese indicador conserva el proceso del servidor.

`Assets/Branding/windows` prepara Square44x44Logo, Square150x150Logo y StoreLogo a escalas 100–400 para el empaquetado MSIX posterior; no implica publicación ni firma en la tienda. Los tamaños siguen la [guía oficial de iconos de Windows](https://learn.microsoft.com/es-es/windows/apps/design/iconography/app-icon-construction).
