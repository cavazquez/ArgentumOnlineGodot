# Argentum Online Godot para ProyectoAO

<p align="center">
  <a href="https://github.com/cavazquez/ArgentumOnlineGodot/actions/workflows/client-linux.yml"><img src="https://img.shields.io/github/actions/workflow/status/cavazquez/ArgentumOnlineGodot/client-linux.yml?branch=main&amp;label=CI&amp;logo=github" alt="CI del cliente"></a>
  <a href="https://github.com/cavazquez/ArgentumOnlineGodot/actions/workflows/release.yml"><img src="https://img.shields.io/github/actions/workflow/status/cavazquez/ArgentumOnlineGodot/release.yml?label=Release&amp;logo=github" alt="Workflow de Release"></a>
  <a href="https://github.com/cavazquez/ArgentumOnlineGodot/releases"><img src="https://img.shields.io/github/v/release/cavazquez/ArgentumOnlineGodot?include_prereleases&amp;sort=date&amp;label=release" alt="Última release, incluidas versiones de prueba"></a>
  <a href="https://github.com/cavazquez/ArgentumOnlineGodot/releases"><img src="https://img.shields.io/github/downloads/cavazquez/ArgentumOnlineGodot/total" alt="Descargas de GitHub Releases"></a>
  <a href="docs/FUNCIONES.md"><img src="https://img.shields.io/badge/docs-referencia-007ec6?logo=readthedocs&amp;logoColor=white" alt="Documentación del cliente"></a>
  <a href=".godot-version"><img src="https://img.shields.io/badge/Godot-4.7.2-478CBF?logo=godotengine&amp;logoColor=white" alt="Godot 4.7.2"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/cavazquez/ArgentumOnlineGodot" alt="Licencia MIT"></a>
</p>

<p align="center">
  <a href="https://snapcraft.io/pyao-client"><img src="https://img.shields.io/snapcraft/v/pyao-client/latest/edge?arch=amd64&amp;label=snap%20edge&amp;logo=snapcraft" alt="Versión de pyao-client en Snap latest/edge para amd64"></a>
  <a href="https://github.com/cavazquez/homebrew-pyao#macos-homebrew"><img src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fcavazquez%2Fhomebrew-pyao%2Fmain%2Fchannel-manifest.json&amp;query=%24.version&amp;label=homebrew&amp;logo=homebrew&amp;color=FBB040" alt="Versión publicada mediante Homebrew para macOS Intel y Apple Silicon"></a>
  <a href="https://github.com/cavazquez/homebrew-pyao#debian-y-ubuntu-apt-firmado"><img src="https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fcavazquez%2Fhomebrew-pyao%2Fmain%2Fchannel-manifest.json&amp;query=%24.version&amp;label=apt&amp;logo=debian&amp;color=007ec6" alt="Versión publicada en APT firmado para amd64 y arm64"></a>
  <a href="https://github.com/cavazquez/ArgentumOnlineGodot/issues/160"><img src="https://img.shields.io/badge/Microsoft%20Store-pendiente-lightgrey" alt="Microsoft Store pendiente: issue 160"></a>
  <a href="https://github.com/microsoft/winget-pkgs/pull/458434"><img src="https://img.shields.io/badge/winget-en%20revisi%C3%B3n-lightgrey" alt="Propuesta WinGet en revisión: Cavazquez.PyAOClient"></a>
</p>

<p align="center">
  <a href="https://github.com/cavazquez/ArgentumOnlineGodot">Proyecto</a> ·
  <a href="docs">Documentación</a> ·
  <a href="https://github.com/cavazquez/ArgentumOnlineGodot/releases">Releases</a>
</p>

Homebrew y APT enlazan sus instrucciones de instalación verificadas. WinGet enlaza su propuesta en revisión; Microsoft Store sigue pendiente.

Instalación y actualización: [Homebrew, APT firmado y estado de WinGet](https://github.com/cavazquez/homebrew-pyao#readme).

Cliente Godot de ProyectoAO, basado en el [port de brian-christopher](https://github.com/brian-christopher/ArgentumOnlineGodot) del cliente Argentum Online 0.13.3 liberado por Shak.

Descargas de pruebas: [releases del cliente y Snap](https://github.com/cavazquez/ArgentumOnlineGodot/releases) · [releases del servidor](https://github.com/cavazquez/pyao-server/releases). Instalar la misma versión en ambos. GitHub excluye las prereleases de `/releases/latest`; los indicadores superiores incluyen las RC publicadas.

Los PR ejecutan comprobaciones de herramientas, Godot, protocolo y TLS sin exportar
el juego. Las compilaciones y la publicación requieren una ejecución manual;
ver [CI y releases](docs/CI_RELEASES.md).

La [auditoría cruzada del protocolo](https://github.com/cavazquez/pyao-server/blob/main/docs/audits/protocol-583/README.md)
registra los mensajes, sus consumidores, las pruebas y los faltantes de ambos proyectos.

## Servidor y alcance de la 1.0

El servidor objetivo es [cavazquez/pyao-server](https://github.com/cavazquez/pyao-server). El [issue #123 del servidor](https://github.com/cavazquez/pyao-server/issues/123) contiene el alcance compartido, el orden de implementación y las pruebas para aprobar ambos proyectos juntos. Su documento versionado es `docs/development/ALCANCE_1_0.md` en el repositorio del servidor.

La candidata actual incluye Linux, Windows, macOS, web y Snap `pyao-client` en `latest/edge` para AMD64 y ARM64. Conserva login/alta directos, ciudades, clases, mapas, recursos e inventario de 30 slots propios de pyao. Los ports de Hide Zone se adaptan a ese contrato; el login y el dataset de AO Libre no sustituyen los de ProyectoAO.

El cierre se prueba con dos clientes Godot reales contra servidor y Redis aislados: cuentas, mapa, chat, inventario, economía, combate, magia, funciones sociales y reconexión. La campaña actual también valida los paquetes nativos de las cinco plataformas, web, ARM64, quests y facciones. Las botas visibles y Microsoft Store siguen pendientes.

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

La aprobación de la 1.0 se registra para un par exacto de commits con las pruebas
del alcance. Un issue cerrado o un ensayo corto no sustituyen la aceptación R10.

Para repetir la comprobación del motor: `GODOT_BIN=/ruta/godot ./tools/smoke-godot.sh`. Para exportar Linux, seguir [docs/GODOT.md](docs/GODOT.md).

Las acciones de las 22 habilidades, asignación, fabricación y pruebas gráficas
de los 45 hechizos están documentadas en [docs/MECANICAS_AO.md](docs/MECANICAS_AO.md).

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
plazo, cancelación, recuperación del formulario y segundo intento. Incluye una
ráfaga de 480 registros TLS: debe negociar en menos de tres segundos a 60 FPS,
con presupuesto de 256 lecturas y 64 KiB por cuadro. La integración
completa del juego sobre este transporte se valida con el recorrido de #60.


### Detalles de clan

`/detallesclan` abre la vista confirmada por pyao: fundador, fecha, líder, sitio,
miembros, alianzas, guerras, códice y descripción. Actualizar usa el paquete 69.
Abandonar pide confirmación, envía 72 y consulta nuevamente el estado; la ventana
no anuncia éxito por su cuenta. Los comandos propios de clan y party se conservan.
Las acciones de administración sin handler permanecen deshabilitadas.

La distribución Linux como `pyao-client` se construye con la receta de
[Snap](docs/SNAP.md), que incluye procedencia del commit y el motor fijado.

El cliente y el servidor usan la misma versión de producto: `1.0.0rc5`. Snap toma ese valor de `project.godot`; la procedencia conserva además el commit y el motor.

`tools/release-pair.py` prepara los tres Snaps y publica servidor/cliente como
una entrega coordinada: valida commits fusionados, CI, hashes, R01–R10 y el
ensayo de actualización antes de promover los canales. El
[procedimiento Snap](docs/SNAP.md) documenta los recibos y la recuperación
completa del par si falla una promoción.

La [integración con dos Godot](docs/INTEGRACION.md) rechaza pares con versiones distintas y comprueba TLS, pantallas reales y cierre ordenado. CI instala además el Snap estricto, recorre login/mapa/chat/inventario con teclado y mouse X11, verifica audio con un sink de prueba y conserva preferencias al actualizar.

El workflow `Login entre Snaps publicados` ejecuta `tools/snap-pair-login.py`
contra las revisiones de Store indicadas explícitamente. Arranca ambos
con `snap run`, crea una cuenta por TLS y maneja la UI de producción por X11.
Mide dos logins hasta que se ven mapa, minimapa, consola e inventario; comprueba
movimiento e inventario en Redis descartable y vuelve a ingresar después de
reiniciar el servidor. Conserva capturas, hashes, procedencia y tiempos como
artefactos del ensayo. Requiere un usuario sin perfil previo de juego.
`workflow_dispatch` permite indicar las revisiones, commits y SHA256 de cada
entrega coordinada; no genera paquetes ni publica canales.

El recorrido completo de [#106](https://github.com/cavazquez/ArgentumOnlineGodot/issues/106)
usa `tools/r10_world.py`, el controlador de pantallas `tests/r10_client.gd` y
`tests/r10_fixture.toml`. `tools/export-linux.sh --r10` genera el ejecutable de
aceptación en `build/r10/`; el Snap se construye con el preset de producción.
El smoke recompila ambos drivers desde su texto con los autoloads del proyecto
cargados para validar también el arnés.

Los sprites de calzado de The Mana World conservan su licencia GPL-2.0 y
atribución independiente; el código propio sigue bajo MIT. Ver
[licencia y procedencia del calzado](Assets/Equipment/Boots/LICENSE.txt).
