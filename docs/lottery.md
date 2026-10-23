# Lotería física

En Ullathorpe, mapa 1 (53,52), seleccionar al Lotero de Ullathorpe abre la ventana.
Su nombre es visible en ambos clientes. Para apostar hay que estar vivo, en el
mismo mapa, a tres casillas como máximo y con esa instancia seleccionada.
La entrada «Lotería» de Mundo permite consultar el resultado desde lejos; no
habilita apuestas a distancia. El servidor verifica cada cobro.

La ventana muestra bruto, comisión, neto, pozo, aporte acumulado, porcentaje y
cuenta regresiva orientativa. Antes del cobro pide confirmar el importe. El
mínimo es 100 oro y la comisión acumulada es 1%, redondeada hacia arriba. Con
apuestas de 100 y 300 se participa con 99 y 297: 25%/75%, premio 396.
Las apuestas se acumulan por personaje; no hay ventaja por dividirlas.

La primera apuesta inicia la ronda (cinco minutos por defecto). El reloj local
sólo orienta: no decide si entra un aporte, ni su saldo o ganador. Alejarse o salir
del juego conserva la participación. La devaluación diaria también afecta al
pozo y a premios pendientes. Si no hay capacidad para todo el premio, el ganador
debe liberar oro en bolsillo/banco y el servidor reintentará el crédito íntegro.

Si se pierde una respuesta, «Reintentar la misma operación» conserva el ID del
comprobante; no se crea otra apuesta. Tras reconectar consultar el aporte vigente.
El nombre histórico y premio del último ganador siguen visibles hasta pagar otro
sorteo y se anuncian en chat. Una ronda vacía/cancelada no borra ese resultado.
Se muestran también compromiso, semilla revelada, hash y boleto de la auditoría.

Reglas, persistencia y límites de la auditoría:
[servidor](https://github.com/cavazquez/pyao-server/blob/main/docs/systems/lottery.md).

## Ensayo reproducible

`tools/lottery_world.py` usa dos Godot reales con Redis/AOF y cuentas descartables.
Interactúa con el NPC, modifica el SpinBox y confirma el diálogo; consulta Redis
independientemente para comprobar cobros/premio y reinicia el servidor.
El ensayo desde fuentes no se presenta como una exportación nativa publicada.

```sh
uv run --project ../pyao-server --locked python tools/integration-world.py \
  --server-project ../pyao-server --source --godot /ruta/a/godot \
  --output /ruta/a/evidencia --seconds 10 --scenario lottery --client-audio PulseAudio
```

La ronda de este escenario dura los 300 segundos productivos, con ambos jugadores
desconectados al cerrar; `--seconds 10` controla la fase final del harness y no
acorta el sorteo. El escenario no modifica Redis del operador ni publica paquetes.
