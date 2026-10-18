# Argentum Online Godot para ProyectoAO

Cliente Godot de ProyectoAO, basado en el [port de brian-christopher](https://github.com/brian-christopher/ArgentumOnlineGodot) del cliente Argentum Online 0.13.3 liberado por Shak.

## Servidor y alcance de la 1.0

El servidor objetivo es [cavazquez/pyao-server](https://github.com/cavazquez/pyao-server). El [issue #123 del servidor](https://github.com/cavazquez/pyao-server/issues/123) contiene el alcance compartido, el orden de implementación y las pruebas para aprobar ambos proyectos juntos. Su documento versionado es `docs/development/ALCANCE_1_0.md` en el repositorio del servidor.

La primera distribución incluye Linux amd64 y Snap `pyao-client` en `latest/edge`. Conserva login/alta directos, ciudades, clases, mapas, recursos e inventario de 30 slots propios de pyao. Los ports de Hide Zone se adaptan a ese contrato; el login y el dataset de AO Libre no sustituyen los de ProyectoAO.

El cierre se prueba con dos clientes Godot reales contra servidor y Redis aislados: cuentas, mapa, chat, inventario, economía, combate, magia, funciones sociales y reconexión. La distribución inicial no exige web, Windows, macOS, ARM64, quests ni facciones.

## Ejecutar el proyecto en desarrollo

1. Clonar este fork:

   ```bash
   git clone https://github.com/cavazquez/ArgentumOnlineGodot.git
   cd ArgentumOnlineGodot
   ```

2. Instalar **Godot 4.7.2 stable Standard** y **export templates 4.7.2.stable**. La versión está fijada en [`.godot-version`](.godot-version); las descargas, checksums y comprobaciones están en [la guía del motor](docs/GODOT.md). Se mantiene GL Compatibility.
3. Importar `project.godot` con el motor validado y ejecutar la escena principal.
4. Configurar un servidor pyao de prueba siguiendo su README. Python, dependencias y ejecución del servidor se gestionan con **uv**; Redis se ejecuta por separado.

## Orden de distribución

- [#10](https://github.com/cavazquez/ArgentumOnlineGodot/issues/10): Godot 4.7.2 y templates fijados; importación, escenas y exportación Linux verificadas.
- [#8](https://github.com/cavazquez/ArgentumOnlineGodot/issues/8) y [#11](https://github.com/cavazquez/ArgentumOnlineGodot/issues/11): rutas Linux e importación/exportación en CI.
- Resolver seguridad, protocolo y gameplay en el orden del alcance compartido.
- [#60](https://github.com/cavazquez/ArgentumOnlineGodot/issues/60): recorrido automatizado del cliente real con servidor y Redis.
- [#46](https://github.com/cavazquez/ArgentumOnlineGodot/issues/46): construir, instalar, probar y publicar el Snap después de las puertas de calidad y seguridad.

El plan de la 1.0 está definido; su implementación y aprobación siguen pendientes de los issues y pruebas enlazados. La exportación Linux del motor está verificada; la integración completa con servidor y la distribución Snap siguen los issues enlazados.

Para repetir la comprobación del motor: `GODOT_BIN=/ruta/godot ./tools/smoke-godot.sh`. Para exportar Linux, seguir [docs/GODOT.md](docs/GODOT.md).

El cliente sólo recuerda el nombre de usuario. Al abrir una instalación antigua migra `saved_credentials.dat` a `login_preferences.cfg` y elimina el archivo legado con contraseña. Los logs de autenticación conservan únicamente el tipo de operación.
