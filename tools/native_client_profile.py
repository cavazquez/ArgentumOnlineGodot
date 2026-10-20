"""Aislamiento de user:// para fixtures Windows/macOS sin cambiar HOME del host."""

import hashlib
import json
from pathlib import Path
import shutil


def isolated_copy(executable, work, index, platform_name):
    """Copia los mismos bytes; sólo el override de aceptación elige un perfil propio."""
    if platform_name not in {"darwin", "win32"}:
        return executable
    destination = work / f"native-client-{index}"
    if platform_name == "darwin":
        bundle = next(path for path in executable.parents if path.suffix == ".app")
        target = destination / bundle.name
        shutil.copytree(bundle, target)
        copied = target / executable.relative_to(bundle)
    else:
        shutil.copytree(executable.parent, destination)
        copied = destination / executable.name
    # Los overrides ya cambian main_scene a la entrada de aceptación. Cada
    # instancia necesita también su user://: XDG no se aplica en estos dos SO.
    profile = "PyAO-validation-" + work.name + "-" + str(index)
    override = copied.parent / "override.cfg"
    original = (executable.parent / "override.cfg").read_text()
    if original.strip() != '[application]\nrun/main_scene="res://tests/integration_world.tscn"\nrun/flush_stdout_on_print=true':
        raise ValueError("Override de aceptación distinto del perfil conocido")
    override.write_text(original.rstrip() + '\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name=' + json.dumps(profile) + '\n')
    if platform_name == "darwin":
        shutil.copy2(override, copied.parent.parent / "Resources/override.cfg")
    source_sha = hashlib.sha256(executable.read_bytes()).hexdigest()
    copied_sha = hashlib.sha256(copied.read_bytes()).hexdigest()
    if source_sha != copied_sha:
        raise ValueError("La copia de la fixture alteró el ejecutable")
    (work / f"native-profile-{index}.json").write_text(json.dumps({"profile": profile, "source_sha256": source_sha, "runtime_sha256": copied_sha, "override_only": ["main_scene", "flush_stdout_on_print", "use_custom_user_dir", "custom_user_dir_name"]}, indent=2) + "\n")
    return copied
