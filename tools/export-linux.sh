#!/usr/bin/env bash
# Exportación reproducible con diagnóstico estricto y una repetición acotada del cache frío.
set -euo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
godot_bin=${GODOT_BIN:-godot}
"$project_root/tools/check-godot.sh" --templates
mkdir -p "$project_root/build"
run_export() {
  local log_file=$1
  local status=0
  LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a "$godot_bin" --path "$project_root" \
    --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
    --rendering-method gl_compatibility --export-release 'Linux Desktop' \
    "$project_root/build/pyao-client.x86_64" >"$log_file" 2>&1 || status=$?
  cat "$log_file"
  return "$status"
}
initial_log="$project_root/build/export-linux-initial.log"
final_log="$project_root/build/export-linux.log"
run_export "$initial_log"
classification=0
python3 "$project_root/tools/check-export-log.py" "$initial_log" || classification=$?
case "$classification" in
  0) cp "$initial_log" "$final_log" ;;
  2)
    echo "Godot inicializó la caché de exportación con imágenes vacías al salir; se repite una vez."
    run_export "$final_log"
    # La segunda exportación debe ser totalmente limpia, incluso del diagnóstico conocido.
    python3 "$project_root/tools/check-export-log.py" "$final_log"
    ;;
  *) exit 1 ;;
esac
test -s "$project_root/build/pyao-client.x86_64"
