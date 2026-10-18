#!/usr/bin/env python3
"""Recorre el cliente instalado usando XTest sobre un Xvfb exclusivo del ensayo.

Requiere Python del sistema con Pillow y libXtst. No carga código del checkout
en el juego. La contraseña efímera llega por entorno y nunca por argumentos.
"""
import argparse
import ctypes
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time

from PIL import ImageGrab


class Input:
    def __init__(self):
        self.x = ctypes.CDLL("libX11.so.6")
        self.t = ctypes.CDLL("libXtst.so.6")
        self.x.XOpenDisplay.argtypes = [ctypes.c_char_p]
        self.x.XOpenDisplay.restype = ctypes.c_void_p
        self.display = self.x.XOpenDisplay(None)
        if not self.display:
            raise RuntimeError("Falta el Xvfb propio del ensayo")
        self.x.XStringToKeysym.argtypes = [ctypes.c_char_p]
        self.x.XStringToKeysym.restype = ctypes.c_ulong
        self.x.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        self.x.XKeysymToKeycode.restype = ctypes.c_uint
        self.x.XFlush.argtypes = [ctypes.c_void_p]
        self.t.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
        self.t.XTestFakeButtonEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
        self.t.XTestFakeMotionEvent.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]

    def key(self, name, pressed):
        code = self.x.XKeysymToKeycode(self.display, self.x.XStringToKeysym(name.encode()))
        if not code:
            raise RuntimeError("Tecla no disponible en Xvfb")
        self.t.XTestFakeKeyEvent(self.display, code, int(pressed), 0)
        self.x.XFlush(self.display)

    def tap(self, name):
        self.key(name, True)
        self.key(name, False)
        time.sleep(.1)

    def text(self, text):
        for character in text:
            shifted = character.isupper() or character == "_"
            key = "minus" if character in "_-" else character.lower()
            if shifted:
                self.key("Shift_L", True)
            self.tap(key)
            if shifted:
                self.key("Shift_L", False)

    def move(self, x, y):
        self.t.XTestFakeMotionEvent(self.display, -1, x, y, 0)
        self.x.XFlush(self.display)
        time.sleep(.1)

    def button(self, pressed):
        self.t.XTestFakeButtonEvent(self.display, 1, int(pressed), 0)
        self.x.XFlush(self.display)

    def click(self, x, y):
        self.move(x, y)
        self.button(True)
        self.button(False)
        time.sleep(.2)


def main():
    def interrupted(*_):
        raise InterruptedError("Ensayo UI interrumpido")
    signal.signal(signal.SIGTERM, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--ca", type=Path, required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--executable", type=Path, help="Sólo desarrollo local; no acredita confinamiento")
    args = parser.parse_args()
    if not args.executable:
        metadata = subprocess.check_output(["snap", "list", "pyao-client", "--unicode=never"], text=True)
        if metadata.splitlines()[1].split()[1] != args.version:
            raise RuntimeError("El Snap instalado no corresponde a la versión del servidor")
        if not Path("/var/lib/snapd/desktop/applications/pyao-client_pyao-client.desktop").is_file():
            raise RuntimeError("Falta la integración del Snap en el menú de aplicaciones")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    common = output / "standalone-user" if args.executable else Path.home() / "snap/pyao-client/common"
    preferences = common / "data/godot/app_userdata/ArgentumOnlineGodot"
    preferences.mkdir(parents=True, exist_ok=True, mode=0o700)
    config = preferences / "connection.cfg"
    if config.exists():
        raise RuntimeError("El ensayo requiere un perfil nuevo; no se sobreescriben preferencias existentes")
    ca = common / "integration-ca.crt"
    shutil.copyfile(args.ca, ca)
    config.write_text(f'[connection]\nhost="127.0.0.1"\nport={args.port}\ntls=true\nca_path="{ca}"\n')
    environment = dict(os.environ)
    if args.executable:
        environment.update(XDG_DATA_HOME=str(common / "data"), XDG_CONFIG_HOME=str(common / "config"), XDG_CACHE_HOME=str(common / "cache"))
    command = [str(args.executable.resolve())] if args.executable else ["snap", "run", "pyao-client"]
    audio = os.environ.get("PYAO_TEST_AUDIO", "Dummy")
    command += ["--position", "0,0", "--resolution", "800x600", "--audio-driver", audio,
                "--rendering-method", "gl_compatibility", "--display-driver", "x11"]
    with (output / "snap-client.log").open("wb") as log:
        process = subprocess.Popen(command, env=environment, stdout=log, stderr=subprocess.STDOUT, cwd=output)
        try:
            time.sleep(5)
            if process.poll() is not None:
                raise RuntimeError("El cliente instalado no abrió; revisar snap-client.log")
            controls = Input()
            ImageGrab.grab(xdisplay=os.environ["DISPLAY"]).save(output / "snap-login.png")
            controls.click(400, 256)
            controls.text(os.environ["PYAO_TEST_USERNAME"])
            controls.click(365, 317)
            controls.text(os.environ["PYAO_TEST_PASSWORD"])
            controls.click(268, 362)
            controls.click(344, 411)
            deadline = time.monotonic() + 40
            while True:
                screenshot = ImageGrab.grab(xdisplay=os.environ["DISPLAY"])
                colors = screenshot.crop((10, 135, 540, 550)).convert("RGB").getcolors(1000000)
                colored = sum(count for count, (r, g, b) in colors if max(r, g, b) - min(r, g, b) > 30)
                if colored > 10000:
                    break
                if time.monotonic() > deadline or process.poll() is not None:
                    screenshot.save(output / "snap-failure.png")
                    raise TimeoutError("El Snap no llegó al mapa mediante el login real")
                time.sleep(.5)
            screenshot.save(output / "snap-map.png")
            for direction in ("Right", "Down", "Left"):
                controls.key(direction, True)
                time.sleep(.4)
                controls.key(direction, False)
                time.sleep(.4)
            controls.tap("Return")
            controls.text("pyao-snap-installed-chat")
            controls.tap("Return")
            controls.move(744, 340)
            controls.button(True)
            controls.move(700, 290)
            controls.move(615, 180)
            controls.button(False)
            time.sleep(2)
            ImageGrab.grab(xdisplay=os.environ["DISPLAY"]).save(output / "snap-input.png")
            if audio == "PulseAudio":
                streams = subprocess.check_output(["pactl", "list", "short", "sink-inputs"], text=True)
                if not streams.strip():
                    raise RuntimeError("Godot no abrió un stream de audio en el servidor de prueba")
            controls.click(781, 20)
            process.wait(timeout=10)
            if process.returncode != 0:
                raise RuntimeError("El cliente no cerró desde la UI")
            text = (output / "snap-client.log").read_text()
            if "ERROR:" in text or os.environ["PYAO_TEST_PASSWORD"] in text:
                raise RuntimeError("El cliente registró un error o una credencial efímera")
            (output / "snap-ui.json").write_text(json.dumps({"passed": True,
                "installed": args.executable is None, "tls": True, "audio_driver": audio,
                "map_rendered": True, "keyboard_mouse": True, "profile_external": True}, indent=2) + "\n")
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)


if __name__ == "__main__":
    main()
