# Bóveda y ficha de clan confirmadas por el servidor

Implementación coordinada de cliente #234/#235 y servidor #582, #588–#593/#596.

La bóveda permite arrastrar un objeto a otro slot propio, incluido el último y
los ocupados. La grilla no cambia hasta recibir la confirmación del servidor.
Mientras el movimiento está pendiente, bloquea otras transferencias; si falta
el ACK, el botón Reintentar conserva la identidad de la operación. Al alejarse,
morir o cerrar el banco, el servidor rechaza nuevos movimientos.

La ventana Clan muestra códice/descripción, noticias y sitio a sus miembros.
El líder puede editarlos. Cada campo admite 200 caracteres; el servidor valida
también el tamaño total y una URL http/https sin credenciales. Ante conflicto, el
texto publicado se actualiza y el borrador permanece. La acción de conservarlo
sobre la versión nueva requiere revisar los cambios explícitamente. Un cambio
de liderazgo revoca la edición y conserva el texto que estaba escrito.

El protocolo mantiene un solo transporte de intercambio con sesiones y revisiones.
Los IDs antiguos retirados se rechazan; la apertura del mercader es exactamente
un byte. GRUPO no depende de una señal antigua de login. Los plazos y capacidades
de las dos copias de `contract.json` coinciden con las constantes implementadas.

Los writers verifican rangos antes de codificar y Flush comprueba el lote completo.
El framer y los receptores validan las entradas sin confundir fragmentación con
un paquete inválido. La selección de objetivos de magia comparte el temporizador
de lanzamiento normal; los clics rápidos no saltan la cadencia del cliente.

`tools/smoke-godot.sh` ejecuta las fixtures de protocolo, escritores y receptores,
conservación de borradores y ausencia de movimientos bancarios optimistas.
`tools/integration-world.py --scenario storage-protocol` ejecuta la regresión
conjunta con dos clientes y un Redis aislado. El workflow Cliente Linux permite
seleccionar ese escenario al solicitar la campaña gráfica.

La política de persistencia y los detalles de las transacciones se documentan en
[el servidor](https://github.com/cavazquez/pyao-server/blob/main/docs/development/protocol-bank-clans.md).
El perfil Redis recomendado es AOF `always`: el resultado del combate sólo se
publica tras confirmar fsync. Un Redis existente con `everysec` sigue admitido,
pero conserva su espera de hasta un segundo por barrera.
