# Equipamiento individual, calzado y arranque

Esta tanda necesita el servidor de objetos individuales (#565–#570). No se
mantiene el formato anterior de CharacterCreate/CharacterChange: ambos agregan
el ID de botas al final. Servidor y cliente conservan la misma versión común.

Las cinco botas del catálogo usan ObjType 36 y una ranura independiente de la
armadura. El avatar superpone fotogramas originales de The Mana World,
reutilizados sin cambiar sus píxeles, escalados/anclados al cuerpo y con los
pasos sincronizados. El barco y el fantasma ocultan la capa de calzado.
`Assets/Equipment/Boots` contiene los originales, XML, licencia, atribución,
commit y hashes. La licencia del código propio sigue siendo MIT.

Los estados individuales llegan por WORLD_STATE en páginas de hasta cinco
objetos. Sólo se muestran slots propios, bóveda abierta, stock del mercader
cercano y objetos ofrecidos en el intercambio activo. El cliente muestra usos
restantes, creación y vencimiento UTC, condición y estadísticas base/efectivas.
El servidor conserva la autoridad sobre todos esos valores. El HUD se actualiza
al recibir la condición y no se confirma un intercambio sin sus metadatos.
El stock NPC identifica expresamente el próximo ejemplar de su cola; las demás
unidades conservan condiciones individuales.

La pantalla de login coloca TLS y el certificado debajo de la contraseña.
La introducción usa la pista 1; el servidor selecciona la música normal de los
mapas, incluyendo silencio explícito. En web se espera un gesto del usuario.
Cambiar de pantalla o cerrar drena el reproductor, sin multiplicar pistas.

Los PCK externos son opcionales: su ausencia no genera avisos. Si uno existe y
es inválido, el arranque muestra un error. Se comprueban índices, recursos
esenciales y los 290 mapas antes de anunciar que la instalación está cargada.
El HUD conserva la navegación y retira únicamente el texto «Navegando».

## Pruebas

- `tools/smoke-godot.sh`: escenas, contrato, 386 referencias de equipo y
  comprobaciones de login/condiciones.
- `res://tests/item_polish_smoke.tscn -- --real-audio`: con PulseAudio mide la
  salida de tres pistas; la variante sin ese argumento sirve para CI sin audio.
- `tools/integration-world.py --scenario durable-items`: dos clientes gráficos,
  cinco botas, ambos tamaños de personaje, cuatro direcciones, reconexión,
  cruces de mapa, intercambio del mismo ejemplar, banco/suelo, vencimiento,
  combate y las tres actividades de recolección. Es una regresión funcional;
  no acredita por sí sola la aceptación prolongada de 30 minutos.
