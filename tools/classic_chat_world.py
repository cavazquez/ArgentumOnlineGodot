"""Chat clásico por dos Godot gráficos, TLS y Redis descartable del harness.

Las acciones se envían mediante el campo de chat real. La fixture sólo prepara
la cuenta GM y las posiciones con las sesiones desconectadas.
"""

import json
import time

from r10_world import ROOT, R10World, prepare_fixture

REQUIRED = {"classic-permissions", "classic-player", "classic-gm", "classic-world", "classic-reconnect"}


def acceptance(steps, _seconds, *, graphical, **_kwargs):
    missing = sorted(REQUIRED - {row["id"] for row in steps if row.get("passed")})
    return {"test_execution_passed": graphical and not missing, "missing": missing,
            "r10_gameplay_passed": False}


class ClassicChatWorld(R10World):
    def say(self, user, text, expected=None):
        self.command(user, "chat", text=text)
        if expected:
            return self.console(user, expected)

    def run(self, locations):
        self.deadline = time.monotonic() + 900
        self.wait(lambda: all("INTEGRATION_WORLD: READY" in
                  (self.output / f"godot-{i}.log").read_text() for i in (1, 2)),
                  "dos clientes de chat clásico", 90)
        with self.fixture.client() as store:
            self.ids = {i: int(store.hget(f"account:{self.names[i-1]}:data", "user_id"))
                        for i in (1, 2)}
            x, y = locations["base"]
            self.relocate(store, {1: (1, x, y), 2: (1, x+1, y)}, reset=True,
                          accounts={1: {"is_gm": "1"}})
            self.say(2, "/DESC Explorador de prueba", "Descripción actualizada")
            self.wait(lambda: store.hget(f"player:{self.ids[2]}:user_stats", "description")
                      == "Explorador de prueba", "descripción persistida")
            self.command(1, "click", x=x+1, y=y)
            self.console(1, "Explorador de prueba")
            for text, kind in (("/GM Ayuda del ensayo", "help"),
                               ("/_BUG Error del ensayo", "bug"),
                               ("/ROL Historia del ensayo", "role"),
                               ("/DENUNCIAR Denuncia del ensayo", "denounce")):
                self.say(2, text, "registrad")
                self.wait(lambda kind=kind: store.hlen(f"chat:reports:{kind}") == 1,
                          "reporte durable " + kind)
            self.say(1, "/SHOW SOS", "Ayuda del ensayo")
            self.say(1, "/SHOW BUGS", "Error del ensayo")
            self.say(1, "/BORRAR SOS", "eliminadas")
            if store.hlen("chat:reports:help") or store.hlen("chat:reports:bug") != 1:
                raise AssertionError("BORRAR alteró una cola ajena a SOS")
            self.passed("classic-player", "Descripción seleccionable y reportes privados persistidos")

            self.say(1, f"/MOD {self.names[1]} ORO 12345", "Personaje actualizado")
            self.view(2, lambda v: v["gold"] == 12345, "oro administrativo actualizado en el cliente afectado")
            self.say(1, f"/INFO {self.names[1]}", self.names[1])
            self.say(1, "/MAPMSG classic-map-message")
            for viewer in (1, 2): self.console(viewer, "classic-map-message")
            self.say(1, "/GMSG classic-gm-private")
            self.console(1, "classic-gm-private")
            if "classic-gm-private" in self.command(2, "snapshot")["console"]:
                raise AssertionError("GMSG se mostró a un jugador común")
            self.say(1, "/SHOWNAME", "desactivado")
            for viewer in (1, 2):
                self.view(viewer, lambda v: not v["character_names"][str(self.ids[1])]["visible"],
                          "nombre GM oculto en ambos clientes")
            self.say(1, "/SHOWNAME", "activado")
            for viewer in (1, 2):
                self.view(viewer, lambda v: v["character_names"][str(self.ids[1])]["visible"],
                          "nombre GM restaurado en ambos clientes")
            self.passed("classic-gm", "Edición, audiencias y etiqueta compartida con autorización")

            self.command(1, "click", x=x, y=y-1)
            self.say(1, "/BLOQ", "persistido")
            self.command(1, "move", action="ui_up")
            self.view(1, lambda v: (v["x"], v["y"]) == (x, y), "colisión editada aplicada al caminar")
            self.say(1, "/BLOQ", "persistido")
            self.command(1, "step", action="ui_up")
            self.view(1, lambda v: (v["x"], v["y"]) == (x, y-1), "casilla desbloqueada transitable")
            self.say(1, "/MODMAPINFO NOMBRE Ciudad del ensayo", "name = Ciudad del ensayo")
            self.say(1, "/FORCEMIDIMAP 2 1", "2 jugador")
            self.say(1, "/GUARDAMAPA", "Checkpoint")
            if not store.exists("world:map:saved:1"):
                raise AssertionError("El checkpoint no quedó en Redis")
            self.passed("classic-world", "Colisión consumida por WALK, metadatos y checkpoint persistidos")
            catalog = json.loads((ROOT / "protocol/chat_commands.json").read_text())["commands"]
            denied = [row["name"] for row in catalog if row["role"] == "gm"]
            self.command(2, "capture_reset", label="classic-permissions")
            for name in denied:
                prior = self.command(2, "snapshot")
                before = prior["server_console_count"]
                offset = len(prior["fx_packets"])
                expected = {
                    "/METRICS": "Diagnóstico reservado a administración.",
                    "/BAN": "No tienes permisos de moderación.",
                    "/UNBAN": "No tienes permisos de moderación.",
                    "/MUTE": "No tienes permisos de moderación.",
                    "/UNMUTE": "No tienes permisos de moderación.",
                }.get(name, "No tienes permisos de Game Master.")
                self.say(2, name + " invalid-private-argument")
                self.view(2, lambda v: v["server_console_count"] > before and any(
                              p.get("kind") == "console" and p.get("message") == expected
                              for p in v["fx_packets"][offset:]),
                          "respuesta privada del servidor a " + name)
            view = self.command(2, "snapshot")
            refusals = [p for p in view["fx_packets"] if p.get("kind") == "console"
                        and p.get("message") in {"No tienes permisos de Game Master.",
                            "Diagnóstico reservado a administración.",
                            "No tienes permisos de moderación."}]
            if len(refusals) != len(denied):
                raise AssertionError("Alguna ruta GM no rechazó al jugador antes de interpretar argumentos")
            if "invalid-private-argument" in self.command(1, "snapshot")["console"]:
                raise AssertionError("Se filtraron argumentos de un comando privado")
            self.say(2, "/METRICS_EXTRA never-public-canary", "Comando desconocido")
            if "never-public-canary" in self.command(1, "snapshot")["console"]:
                raise AssertionError("Un prefijo desconocido se difundió como chat público")
            self.passed("classic-permissions", "Todas las rutas GM rechazan a un jugador por TLS",
                        commands=denied, arguments_not_broadcast=True)

            for viewer in (1, 2): self.command(viewer, "capture", label="classic-chat")

            for user in (1, 2):
                self.command(user, "logout")
                self.wait(lambda user=user: not store.exists(f"session:{self.ids[user]}:owner"),
                          "liberar sesión clásica")
                self.command(user, "login")
            self.view(2, lambda v: v["gold"] == 12345, "saldo conservado tras reconectar")
            self.say(1, f"/INFO {self.names[1]}", "Explorador de prueba")
            self.passed("classic-reconnect", "Descripciones, saldo, roles y mundo sobreviven la reconexión")
        for user in (1, 2): self.command(user, "soak")
        return self.steps
