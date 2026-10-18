# Acciones disponibles del cliente

`protocol/contract.json`, dirección `client`, es la matriz versionada de IDs,
campos y estado del backend. `supported` permite las acciones base; `unsupported`
impide emitir bytes aunque exista un writer heredado. Las extensiones requieren
además el bit aceptado por la conexión actual. Reconectar borra esos bits.

La validación se aplica a todos los writers y a los controles de las ventanas.
Trabajo, party, detalles/salida de clan, banco, comercio y mover inventario siguen
sus IDs propios de pyao. No se bloquean por pertenecer a una categoría que tenga
otras operaciones pendientes.

Mientras no exista soporte negociado, el cambio de contraseña y la asignación de
habilidades se muestran sin posibilidad de guardar. Entrenamiento, SpellMacro,
MOVE_BANK, crafting, HOME y administración avanzada de guild permanecen pendientes;
el cliente explica su indisponibilidad sin sustituirlos por comandos GM. Registrar
sus IDs o conservar un writer no cuenta como implementar esas funciones.

Enviar una solicitud sólo inicia una operación. El éxito debe provenir del estado
confirmado por el servidor; las ventanas no deben modificar definitivamente puntos
o credenciales por el solo hecho de escribir al transporte. El flujo de cuenta/hash
de AO Libre no forma parte del login directo de pyao.
