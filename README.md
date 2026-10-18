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

El formulario conecta por **TLS con verificación de certificado y hostname** de
forma predeterminada. Usar el nombre presente en el certificado del servidor;
para una CA privada, indicar su archivo PEM en `CA propia`. Sin ese campo se usa
la confianza estándar de Godot. Un certificado inválido, vencido o de otro nombre
produce error visible y no envía credenciales ni cambia automáticamente a TCP.
El intento completo, incluido el handshake, vence a los 10 segundos y admite
cancelación y reintento. Para desarrollo local en claro, desmarcar explícitamente
TLS; la elección, endpoint y ruta de CA se guardan sin contraseñas.

`GODOT_BIN=/ruta/godot python3 tools/smoke-tls.py` genera certificados temporales y
comprueba Godot real contra endpoints locales: confianza, nombre, vencimiento,
plazo, cancelación, recuperación del formulario y segundo intento. La integración
completa del juego sobre este transporte se valida con el recorrido de #60.


### Detalles de clan

`/detallesclan` abre la vista confirmada por pyao: fundador, fecha, líder, sitio,
miembros, alianzas, guerras, códice y descripción. Actualizar usa el paquete 69.
Abandonar pide confirmación, envía 72 y consulta nuevamente el estado; la ventana
no anuncia éxito por su cuenta. Los comandos propios de clan y party se conservan.
Las acciones de administración sin handler permanecen deshabilitadas.

La distribución Linux como `pyao-client` se construye con la receta de
[Snap](docs/SNAP.md), que incluye procedencia del commit y el motor fijado.

El cliente y el servidor usan la misma versión de producto: `1.0.0rc1` para el candidato RC1. Snap toma ese valor de `project.godot`; la procedencia conserva además el commit y el motor.

La [integración con dos Godot](docs/INTEGRACION.md) rechaza pares con versiones distintas y comprueba TLS, pantallas reales y cierre ordenado. CI instala además el Snap estricto, recorre login/mapa/chat/inventario con teclado y mouse X11, verifica audio con un sink de prueba y conserva preferencias al actualizar.
