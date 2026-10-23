# Equipo y mochila separados

Cada ejemplar se muestra en MOCHILA mientras está sin equipar y sólo en su
ranura de EQUIPO después de confirmarse el equipamiento. Retirarlo lo devuelve
a MOCHILA; reemplazarlo devuelve la pieza anterior. La selección, el teclado
y el arrastre omiten las piezas equipadas, conservando sus índices de protocolo.
El almacenamiento, la capacidad y las validaciones del servidor se mantienen.

Las herramientas se usan desde el selector de su ranura o con U cuando no hay
otro objeto seleccionado en la mochila. Un selector obsoleto no puede equipar,
quitar ni usar otra pieza después de cambiar su identidad o estado equipado.
Las operaciones siguen esperando la confirmación del servidor.

Cliente `667c5445c6cd22c85ff9468986e538a6a0323943`, exportado con Godot 4.7.2
oficial desde checkout limpio; servidor `d933f701f811a517a0b8512cee46f7b22725eafd`
instalado desde wheel. Ambos conservan `1.0.0rc6`.

[Resultado nativo](native-result.json), [14 etapas](scenarios.json) y
[comprobaciones](verification.json). Dos clientes gráficos con TLS, PulseAudio
y Redis 8.10.2/AOF aislado. Se verificó la exclusión mutua mochila/equipo en ambos
personajes, reemplazos, reconexión, portales y desequipamiento. También banco,
suelo, intercambio, vencimiento, combate y usos reales de hacha, piquete y caña.
Godot pasó además las pruebas de confirmación pendiente, selección obsoleta,
navegación por teclado, índices originales y controles comerciales.

La observación posterior fue de 17/16 segundos. Es una regresión funcional;
no acredita la aceptación prolongada de treinta minutos ni una publicación
nueva en la Store. Los intentos previos no se usan como evidencia de aprobación.

## Capturas del mismo estado

Primer cliente: [EQUIPO](equipment-client-1.png) y [MOCHILA](backpack-client-1.png).
Segundo cliente: [EQUIPO](equipment-client-2.png) y [MOCHILA](backpack-client-2.png).
