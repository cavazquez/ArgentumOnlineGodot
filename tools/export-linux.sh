#!/usr/bin/env bash
# Exportación reproducible: OpenGL software evita errores del renderer dummy.
set -euo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
godot_bin=${GODOT_BIN:-godot}
"$project_root/tools/check-godot.sh" --templates
mkdir -p "$project_root/build"
# Un primer arranque gráfico inicializa los recursos del editor que el import dummy
# no materializa. Sin este paso, un checkout frío produce tres imágenes vacías al salir.
editor_log="$project_root/build/editor-init.log"
status=0
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a "$godot_bin" --path "$project_root" \
  --editor --rendering-method gl_compatibility --rendering-driver opengl3 \
  --audio-driver Dummy --quit-after 60 >"$editor_log" 2>&1 || status=$?
cat "$editor_log"
if (( status != 0 )); then exit "$status"; fi
if grep -Eq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:)' "$editor_log"; then exit 1; fi
log_file="$project_root/build/export-linux.log"
status=0
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a "$godot_bin" --path "$project_root" \
  --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
  --rendering-method gl_compatibility --export-release 'Linux Desktop' \
  "$project_root/build/pyao-client.x86_64" >"$log_file" 2>&1 || status=$?
cat "$log_file"
if (( status != 0 )); then exit "$status"; fi
if grep -Eq '(^|[[:space:]])(SCRIPT ERROR:|ERROR:)' "$log_file"; then exit 1; fi
test -s "$project_root/build/pyao-client.x86_64"
