# CI y publicación en GitHub

Cada push y PR ejecuta tests de herramientas, importación y compilación de scripts
con Godot oficial verificado, smokes de escenas, privacidad, protocolo y TLS. No
exporta ejecutables ni construye Snaps. `Seguridad y workflows` valida expresiones
y shell con actionlint/ShellCheck, y rechaza dependencias nuevas vulnerables de
severidad alta o crítica. Dependabot revisa Actions semanalmente; en este fork
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
