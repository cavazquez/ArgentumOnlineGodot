# CI y publicación en GitHub

Cada push y PR ejecuta tests de herramientas, importación y compilación de scripts
con Godot oficial verificado, smokes de escenas, privacidad, protocolo y TLS. No
exporta ejecutables ni construye Snaps. `Seguridad y workflows` valida expresiones
y shell con actionlint/ShellCheck, y rechaza dependencias nuevas vulnerables de
severidad alta o crítica. Las revisiones programadas y Dependabot corren sólo el 1 de diciembre de cada año a las 10:00 de Argentina (13:00 UTC); en este fork
GitHub requiere habilitar **Dependabot version updates** en sus ajustes.

## Preparar una nueva entrega

1. Fusionar ambos commits, aprobar sus chequeos y usar la misma versión en
   `project.godot` y `pyproject.toml`. Crear el mismo tag `v<VERSION>` en ambos
   repositorios. Crear tags no compila ni modifica releases.
2. Ejecutar manualmente `Cliente Linux` sobre el tag con `build_packages=true`.
   Esto conserva export de producción con hash y procedencia, Snap estricto y
   pruebas con dos clientes. Los artefactos duran siete días.
3. Preparar las distribuciones y Snaps del servidor siguiendo su guía de CI.
4. Ejecutar `Release GitHub` sobre main, indicando tag y el ID del workflow de
   compilación completo. Por defecto crea un borrador: comprueba commit exacto,
   jobs exitosos (incluidos integración y las cuatro mecánicas), tag fusionado,
   versión del tag homónimo del servidor, procedencia limpia y hashes. Incluye
   ZIP Linux de producción, Snap, manifiesto y SHA256SUMS; nunca exporta el juego.
5. Completar ambos borradores antes de hacer pública la pareja. `publish=true`
   permite hacer público un borrador nuevo dentro de esa ejecución, tras
   descargar y verificar todos los archivos. Para dos borradores ya preparados,
   publicarlos juntos desde GitHub/CLI después de revisarlos. GitHub no ofrece
   una transacción atómica entre dos repositorios.

Una release existente se rechaza; no se sobreescriben assets. Si falla una subida,
queda el borrador para inspección y recuperación manual. Las prereleases siguen
marcadas como tales; `/releases/latest` sólo apunta a versiones estables. Los
lectores de RC deben consultar el listado o el enlace explícito al tag.

La Store se gestiona mediante `tools/release-pair.py`, con aceptación R01–R10 y
promoción coordinada. Estos workflows no publican canales Snap automáticamente.

## Reintentos de carga y verificación

`tools/github_release_upload.py stage` crea el borrador sin subir archivos en
bloque, carga cada asset por separado y descarga el conjunto final para verificar
tamaño y SHA256. Si ya existe un borrador parcial, verifica los archivos presentes
y sólo carga los faltantes. Un archivo diferente o extra bloquea la operación,
sin sobrescribirlo. Una release publicada sólo admite verificar sus bytes.

`--dry-run` valida las fuentes y describe los faltantes sin crear ni publicar.
`verify` comprueba una release existente; `publish` vuelve a verificarla antes de
hacerla pública. Los tres comandos usan `--directory`, `--tag`, `--version`,
`--commit`, `--repository` y admiten `--receipt`. Los workflows conservan sus
recibos JSON y no promueven canales Snap.

Es posible validar un candidato manualmente sobre main antes de crear el tag
final. Se registra y exige el SHA exacto de cada ejecución; ambos tags finales
deben apuntar a esos mismos commits fusionados antes de preparar los borradores.
Un reintento fallido de CI no requiere mover un tag ya publicado.

La prueba Windows usa Redis oficial dentro de WSL2, en un directorio Linux
privado. Se comprueba el kernel real y se rechaza WSL1: sus pausas al crear el
proceso de una copia RDB pueden superar el timeout del juego. La aceptación
conserva AOF con `appendfsync always`, valida un RDB mayor a 32 MiB y su reinicio,
y fuerza otra copia con más de 400.000 claves y los dos clientes conectados.
El recibo registra la latencia del fork y de las respuestas; superar cinco
segundos o perder una sesión mantiene fallida la aceptación.
