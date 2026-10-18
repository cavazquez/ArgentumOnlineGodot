#!/usr/bin/env bash
# Comprueba el motor y los templates oficiales fijados por este repositorio.
set -euo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
expected=$(cat "$project_root/.godot-version")
godot_bin=${GODOT_BIN:-godot}
actual=$("$godot_bin" --version)
case "$actual" in
  "$expected.stable.official."*) ;;
  *) echo "Se requiere Godot $expected stable oficial; recibido: $actual" >&2; exit 1 ;;
esac
if [[ ${1:-} == --templates ]]; then
  templates_dir=${GODOT_TEMPLATES_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$expected.stable}
  [[ $(cat "$templates_dir/version.txt") == "$expected.stable" ]] || {
    echo "Templates de una versión distinta en $templates_dir" >&2; exit 1;
  }
  for template in linux_debug.x86_64 linux_release.x86_64; do
    [[ -s "$templates_dir/$template" ]] || { echo "Falta $template" >&2; exit 1; }
  done
fi
printf '%s\n' "$actual"
