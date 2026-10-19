# Economía y ventanas conectadas al servidor

El HUD abre oro/impuestos, mascotas, grupo y clan. Las ventanas muestran estado
confirmado, esperan el resultado y permiten reintentar la misma operación cuando
el resultado queda pendiente. Expulsar, abandonar y transferir liderazgo requieren
confirmar el destinatario o la consecuencia. Una revisión nueva invalida una
confirmación anterior. El contrato optativo compartido usa `WORLD_STATE = 512` y
el paquete 248; clientes y servidores anteriores conservan su protocolo nativo.

El impuesto diario se aplica al bolsillo y al banco, conectado o desconectado,
con corte a las 00:00 UTC. La ventana muestra tasa, saldos, último cargo y próximo
corte. El cliente no calcula ni descuenta impuestos localmente. Los importes usan
una revisión monetaria del servidor para descartar respuestas atrasadas.

El intercambio entre jugadores muestra nombres, iconos, cantidades y propiedades
del catálogo enviado por el servidor para esa oferta. Hasta identificar todos
los objetos, confirmar permanece deshabilitado y cancelar sigue disponible.

La creación conserva usuario, contraseña, email y seis orígenes. El preview usa
los sprites propios, deja elegir cabeza y orientación y envía la cabeza mostrada.
Los fondos y spawns de `protocol/home-preview.json` proceden de las ciudades de
pyao; si una vista falta se muestra Map1. No se agrega selección múltiple de cuentas.

Los mapas visitados se guardan después de cargar el mapa y recibir el personaje
propio. La identidad local separa host, puerto, TLS y nombre de personaje y no
guarda credenciales. Un archivo corrupto o un ID desconocido no bloquea el ingreso.
El historial del chat conserva un máximo de 50 entradas en memoria y se borra al
desconectar. Tab completa comandos autorizados por el servidor sin enviarlos.

Las preferencias permiten texto instantáneo, alto contraste, letra hasta 24,
intensidad de lluvia, niebla periférica y transiciones. La lluvia usa los WAV
`lluviaoutst`, `lluviaout` y `lluviaoutend` existentes y el bus sfx. No hay destellos
de tormenta. Una capa y un reproductor pertenecen a la pantalla y se vacían al
desconectar. Los interiores no heredan lluvia del mapa anterior.

Las máscaras derivan del viewport y no interceptan clicks. El fade de aparición
respeta invisibilidad; retirar una entidad la elimina inmediatamente. Cambiar de
mapa cancela el tween anterior, espera la posición nueva y evita mezclar el punto
del minimapa. En modo headless se omite la captura de textura del crossfade.

## Pruebas desde el código

`tools/smoke-godot.sh` comprueba motor, credenciales, protocolo, mecánicas y los
casos de estado atrasado, permisos revocados, historial, preferencias, clima y
fabricación fuera de contexto. `tools/integration-world.py --source --scenario
economy` ejecuta la campaña R10 y luego los recorridos de economía con dos Godot.
`--scenario economy-ui` repite sólo esos recorridos. Cada ejecución usa Redis
descartable, certificados efímeros y perfiles locales separados. Los modos fuente
no acreditan un paquete publicado ni construyen binarios.
