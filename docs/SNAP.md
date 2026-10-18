# PyAO Client en Snap

El paquete se llama `pyao-client`, usa confinamiento `strict`, base `core24` y
arquitectura Linux amd64. Esta primera entrega apunta a `latest/edge`. El perfil
gráfico es OpenGL por X11; en escritorios Wayland se usa XWayland. La validación
de Wayland nativo corresponde a otra entrega.

El motor y los templates son exactamente los de `tools/godot-release.json` y se
verifican por SHA256. `snap/toolchain.json` fija Snapcraft 9.1.4, revisión 19274.
La [extensión GPU oficial](https://ubuntu.com/docs/snapcraft/9/reference/extensions/gpu-extension/)
provee las bibliotecas gráficas para core24. El paquete usa red, X11, gráficos,
audio y escritorio. El lanzador guarda configuración, datos y caché bajo
`$SNAP_USER_COMMON`, que se conserva al actualizar.

## Construcción

Con Docker/LXD y Snapcraft disponibles, desde un checkout limpio:

```bash
python3 tools/build-snap.py
```

El comando exige la herramienta fijada, registra el commit y ejecuta Snapcraft en
LXD. El propio build descarga el motor/templates verificados, importa, corre los
smokes y exporta Linux. Incluye el PCK embebido con Maps, Assets, Resources y los
datos cargados dinámicamente; los tests y herramientas no entran en el paquete.
`--allow-dirty` sirve para un artefacto local de revisión y registra `dirty=true`;
no se usa para publicar. La procedencia y licencias quedan también dentro del
Snap en `share/doc/pyao-client/`.

La CI existente ejecuta primero importación/exportación y luego el mismo comando
de Snap en un runner descartable. Conserva paquete, SHA256, log y procedencia.
Si el proveedor LXD local no tiene red, el build puede ejecutarse en CI sin cambiar
las reglas de red del equipo de trabajo.

## Instalación y prueba local

```bash
sudo snap install ./pyao-client_VERSION_amd64.snap --dangerous
pyao-client
snap connections pyao-client
```

Comprobar menú, renderizado, entrada, audio y cierre; crear una cuenta sintética,
entrar a un servidor PyAO compatible, cargar mapa y probar chat/inventario. La
prueba del paquete instalado debe hacerse sin depender del checkout ni del editor
Godot del host. Con una CA de prueba privada, copiar el certificado público al
directorio común del Snap y seleccionarlo desde las preferencias del cliente.
Las claves no se guardan en preferencias.

## Primera publicación

Después de pasar el recorrido conjunto y registrar el resultado de instalación:

```bash
snapcraft login
snapcraft whoami
snapcraft names
snapcraft register pyao-client
snapcraft upload ./pyao-client_VERSION_amd64.snap --release=latest/edge
snapcraft status pyao-client
sudo snap install pyao-client --edge
```

Si el nombre ya está registrado por la cuenta del proyecto, se omite `register`.
Si pertenece a otra cuenta, se registra ese bloqueo y se conserva el nombre
acordado. Adjuntar revisión, versión, resultado de revisión de la Store y prueba
de instalación desde edge. Las credenciales de publicación se mantienen en la
cuenta local/Store y nunca en Git, el paquete o los logs. La CI construye artefactos;
la primera publicación se realiza después de validar la revisión concreta.

Actualizar y volver a una revisión anterior:

```bash
sudo snap refresh pyao-client --edge
sudo snap revert pyao-client
```

La construcción de la receta no acredita una publicación en Store ni una prueba
completa del paquete instalado. Esas evidencias se registran por separado en #46
y en el recorrido conjunto #60.
