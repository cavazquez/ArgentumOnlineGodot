#!/usr/bin/env bash
# Exportación reproducible con diagnóstico estricto y una repetición acotada del cache frío.
set -euo pipefail
project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
godot_bin=${GODOT_BIN:-godot}
preset='Linux Desktop'
output_name='pyao-client'
output_dir="$project_root/build"
if [[ ${1:-} == --r10 ]]; then
  preset='Linux R10 Acceptance'
  output_name='pyao-client-r10'
  output_dir="$project_root/build/r10"
elif [[ $# != 0 ]]; then
  echo 'Uso: export-linux.sh [--r10]' >&2
  exit 2
fi
pyao_export_commit=$(git -C "$project_root" rev-parse HEAD)
pyao_export_clean=false
if [[ -z $(git -C "$project_root" status --porcelain) ]]; then pyao_export_clean=true; fi
python3 "$project_root/tools/write-build-info.py"
"$project_root/tools/check-godot.sh" --templates
mkdir -p "$project_root/build"
mkdir -p "$output_dir"
run_export() {
  local log_file=$1
  local status=0
  LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a "$godot_bin" --path "$project_root" \
    --display-driver x11 --rendering-driver opengl3 --audio-driver Dummy \
    --rendering-method gl_compatibility --export-release "$preset" \
    "$output_dir/$output_name.x86_64" >"$log_file" 2>&1 || status=$?
  cat "$log_file"
  return "$status"
}
log_name='export-linux'
if [[ $output_name == pyao-client-r10 ]]; then log_name='export-r10'; fi
initial_log="$project_root/build/$log_name-initial.log"
final_log="$project_root/build/$log_name.log"
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
test -s "$output_dir/$output_name.x86_64"
if [[ $output_name == pyao-client-r10 ]]; then
  cp "$project_root/tests/r10-export.cfg" "$output_dir/override.cfg"
  python3 - "$output_dir" "$pyao_export_commit" "$pyao_export_clean" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
files = {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
         for name in ('pyao-client-r10.x86_64', 'override.cfg')}
(root / 'provenance.json').write_text(json.dumps({
    'commit': sys.argv[2], 'clean_before_export': sys.argv[3] == 'true',
    'files': files,
}, indent=2) + '\n')
PY
fi
